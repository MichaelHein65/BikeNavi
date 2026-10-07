"""Private, immutable tour journal and versioned HTML drafts."""
import base64
import binascii
import re
from html.parser import HTMLParser
from urllib.parse import urlparse
from uuid import UUID

from fastapi import HTTPException
from pydantic import Field, field_validator, model_validator
from sqlalchemy import JSON, Integer, String, Text, select, update
from sqlalchemy.orm import Mapped, mapped_column

from .models import Coordinate, Model
from .storage import Base, Record, SyncLock

MAX_PHOTO_BYTES = 768 * 1024
MAX_RIDE_PHOTO_BYTES = 20 * 1024 * 1024


class BlogPoint(Model):
    id: UUID
    rideID: UUID
    coordinate: Coordinate
    capturedAt: float = Field(ge=0)
    title: str = Field(min_length=1, max_length=200)
    note: str = Field(default="", max_length=4000)
    photo: str | None = Field(default=None, max_length=MAX_PHOTO_BYTES * 4 // 3 + 4)

    @field_validator("photo")
    @classmethod
    def jpeg_only(cls, value):
        if value is None:
            return value
        try:
            data = base64.b64decode(value, validate=True)
        except (ValueError, binascii.Error) as error:
            raise ValueError("Ungültiges Foto") from error
        if len(data) > MAX_PHOTO_BYTES or not data.startswith(b"\xff\xd8\xff") or not data.endswith(b"\xff\xd9"):
            raise ValueError("Bitte ein verkleinertes JPEG-Foto übertragen")
        return value

    @model_validator(mode="after")
    def has_content(self):
        if not self.photo and not self.note.strip():
            raise ValueError("Bitte ein Foto oder eine Notiz ergänzen")
        return self


class JournalPoint(Base):
    __tablename__ = "blog_points"
    sequence: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    id: Mapped[str] = mapped_column(String(36), unique=True)
    ride_id: Mapped[str] = mapped_column(String(36), index=True)
    payload: Mapped[dict] = mapped_column(JSON)


class BlogDraft(Base):
    __tablename__ = "blog_drafts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    ride_id: Mapped[str] = mapped_column(String(36), index=True)
    html: Mapped[str] = mapped_column(Text)
    metadata_json: Mapped[dict] = mapped_column(JSON)


class ArchivedSources(HTMLParser):
    """Recover source appendices from pre-cache drafts, never article/body text."""
    def __init__(self):
        super().__init__()
        self.sources = []
        self.current = None
        self.field = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "li" and attrs.get("id", "").startswith("source-"):
            self.current = {"title": "", "text": "", "url": "", "language": "web", "distance": None, "_context": ""}
        elif self.current is not None:
            if tag == "a":
                self.current["url"] = attrs.get("href", "")
                self.field = "title"
            elif tag == "p": self.field = "text"
            elif tag == "small": self.field = "_context"

    def handle_data(self, data):
        if self.current is not None and self.field:
            self.current[self.field] += data

    def handle_endtag(self, tag):
        if self.current is None: return
        if tag in ("a", "p", "small"): self.field = None
        if tag == "li":
            url = urlparse(self.current["url"])
            if url.scheme == "https" and url.hostname and not url.username and not url.password and self.current["text"].strip():
                if url.hostname.endswith(".wikipedia.org"):
                    self.current["language"] = url.hostname.split(".")[0]
                    match = re.search(r"ca\.\s*(\d+)\s*m",self.current["_context"])
                    if match: self.current["distance"] = int(match.group(1))
                self.current.pop("_context",None)
                self.current["title"] = re.sub(r"^\[\d+\]\s*", "", self.current["title"])[:300]
                self.current["text"] = self.current["text"][:1500]
                self.sources.append(self.current)
            self.current = None
            self.field = None


class BlogRepository:
    def __init__(self, storage):
        self.sessions = storage.sessions

    def ride(self, session, ride_id):
        ride = session.get(Record, ride_id)
        if not ride or ride.deleted or ride.document["kind"] != "ride":
            raise HTTPException(404, "Die Fahrt ist noch nicht auf dem Pi gespeichert.")
        return ride

    def append(self, point):
        payload = point.model_dump(mode="json", exclude_none=True)
        with self.sessions.begin() as session:
            session.execute(update(SyncLock).where(SyncLock.id == 1).values(generation=SyncLock.generation + 1))
            self.ride(session, str(point.rideID))
            existing = session.scalar(select(JournalPoint).where(JournalPoint.id == str(point.id)))
            if existing:
                if existing.payload != payload:
                    raise HTTPException(409, "Dieser Blog-Ort wurde bereits mit anderem Inhalt gespeichert.")
            else:
                points = session.scalars(select(JournalPoint).where(JournalPoint.ride_id == str(point.rideID))).all()
                if len(points) >= 50 or sum(len(p.payload.get("photo", "")) * 3 // 4 for p in points) + len(point.photo or "") * 3 // 4 > MAX_RIDE_PHOTO_BYTES:
                    raise HTTPException(413, "Diese Fahrt enthält bereits 50 Blog-Orte oder 20 MB Fotos.")
                session.add(JournalPoint(id=str(point.id), ride_id=str(point.rideID), payload=payload))
        return {"accepted": [str(point.id)]}

    def points(self, ride_id, after=0):
        with self.sessions() as session:
            self.ride(session, ride_id)
            entries = session.scalars(select(JournalPoint).where(JournalPoint.ride_id == ride_id, JournalPoint.sequence > after)
                                      .order_by(JournalPoint.sequence).limit(6)).all()
            page = entries[:5]
            return {"points": [p.payload for p in page], "cursor": page[-1].sequence if page else after, "hasMore": len(entries) > 5}

    def snapshot(self, ride_id):
        with self.sessions() as session:
            ride = self.ride(session, ride_id)
            if ride.document["recordingState"] != "finished":
                raise HTTPException(409, "Bitte die Fahrt zuerst beenden und synchronisieren.")
            points = session.scalars(select(JournalPoint).where(JournalPoint.ride_id == ride_id)).all()
            return dict(ride.document), sorted([p.payload for p in points], key=lambda p: (p["capturedAt"], p["id"])), ride.revision

    def save(self, ride_id, revision, point_ids, draft_id, html, metadata):
        with self.sessions.begin() as session:
            session.execute(update(SyncLock).where(SyncLock.id == 1).values(generation=SyncLock.generation + 1))
            ride = self.ride(session, ride_id)
            current_ids = set(session.scalars(select(JournalPoint.id).where(JournalPoint.ride_id == ride_id)).all())
            if ride.revision != revision or current_ids != set(point_ids):
                raise HTTPException(409, "Die Fahrt wurde während der Erstellung geändert. Bitte erneut erstellen.")
            session.add(BlogDraft(id=draft_id, ride_id=ride_id, html=html, metadata_json=metadata))
        return {**metadata, "id": draft_id, "html": html}

    def research_sources(self, ride_id):
        with self.sessions() as session:
            self.ride(session, ride_id)
            # Load one source-rich draft, rather than every photo-bearing HTML version.
            draft = session.scalar(select(BlogDraft).where(BlogDraft.ride_id == ride_id)
                                   .order_by(BlogDraft.metadata_json["sourceCount"].as_integer().desc(),
                                             BlogDraft.metadata_json["createdAt"].as_float().desc()).limit(1))
            if draft is None: return []
            sources = draft.metadata_json.get("researchSources")
            if isinstance(sources, list): return sources[:28]
            parser = ArchivedSources()
            parser.feed(draft.html)
            return parser.sources[:28]

    def latest(self, ride_id):
        with self.sessions() as session:
            self.ride(session, ride_id)
            draft = session.scalar(select(BlogDraft).where(BlogDraft.ride_id == ride_id)
                                   .order_by(BlogDraft.metadata_json["createdAt"].as_float().desc()).limit(1))
            if draft is None:
                raise HTTPException(404, "Für diese Fahrt gibt es noch keinen Blog.")
            return {**draft.metadata_json, "id": draft.id, "html": draft.html}

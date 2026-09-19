import hashlib
import json

from fastapi import HTTPException
from sqlalchemy import JSON, Boolean, Integer, String, create_engine, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from .models import Mutation


class Base(DeclarativeBase):
    pass


class Record(Base):
    __tablename__ = "records"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    revision: Mapped[int] = mapped_column(Integer)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    document: Mapped[dict] = mapped_column(JSON)


class Change(Base):
    __tablename__ = "changes"
    sequence: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    envelope: Mapped[dict] = mapped_column(JSON)


class Receipt(Base):
    __tablename__ = "receipts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    digest: Mapped[str] = mapped_column(String(64))
    envelope: Mapped[dict] = mapped_column(JSON)


# Serializes change-sequence allocation as well as commit ordering. Without this,
# a client could advance its cursor past an uncommitted PostgreSQL sequence value.
class SyncLock(Base):
    __tablename__ = "sync_lock"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    generation: Mapped[int] = mapped_column(Integer, default=0)


class Storage:
    def __init__(self, url: str):
        self.engine = create_engine(url, pool_pre_ping=True)
        self.sessions = sessionmaker(self.engine)
        Base.metadata.create_all(self.engine)
        with self.sessions.begin() as session:
            if session.get(SyncLock, 1) is None:
                session.add(SyncLock(id=1, generation=0))

    def apply(self, mutation: Mutation) -> dict:
        payload = mutation.model_dump(mode="json")
        # Preserve pre-feature receipt hashes when an older client retries.
        if payload["document"]["usesAutomaticTitle"] is None:
            payload["document"].pop("usesAutomaticTitle")
        if payload["document"]["awaitingStart"] is None:
            payload["document"].pop("awaitingStart")
        route = payload["document"].get("route")
        if route and route.get("surfaceSections") is None:
            route.pop("surfaceSections", None)
        digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
        try:
            with self.sessions.begin() as session:
                session.execute(update(SyncLock).where(SyncLock.id == 1).values(
                    generation=SyncLock.generation + 1))
                receipt = session.get(Receipt, str(mutation.mutationID))
                if receipt:
                    if receipt.digest != digest:
                        raise HTTPException(409, "Diese Änderungs-ID wurde bereits anders verwendet.")
                    return receipt.envelope
                record = session.get(Record, str(mutation.document.id))
                revision = record.revision if record else 0
                if revision != mutation.baseRevision:
                    raise HTTPException(409, "Die Planung wurde auf einem anderen Gerät geändert. Beide Fassungen bleiben erhalten.")
                envelope = {"document": payload["document"], "revision": revision + 1,
                            "deleted": mutation.deleted}
                if record:
                    record.revision += 1
                    record.deleted = mutation.deleted
                    record.document = payload["document"]
                else:
                    session.add(Record(id=str(mutation.document.id), revision=1,
                                       deleted=mutation.deleted, document=payload["document"]))
                session.add(Change(envelope=envelope))
                session.add(Receipt(id=str(mutation.mutationID), digest=digest, envelope=envelope))
                return envelope
        except IntegrityError as error:
            raise HTTPException(409, "Gleichzeitige Änderung. Bitte erneut synchronisieren.") from error

    def changes(self, after: int, limit: int = 100) -> dict:
        with self.sessions() as session:
            entries = session.scalars(select(Change).where(Change.sequence > after)
                                      .order_by(Change.sequence).limit(limit + 1)).all()
            page = entries[:limit]
            return {"records": [c.envelope for c in page],
                    "cursor": page[-1].sequence if page else after,
                    "hasMore": len(entries) > limit}

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Coordinate(Model):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    altitude: float | None = None


class Waypoint(Model):
    id: UUID
    name: str = Field(max_length=300)
    coordinate: Coordinate


class Profile(Model):
    bike: Literal["touring", "gravel", "mountain", "road"] = "touring"
    electric: bool = True
    surface: Literal["any", "preferPaved", "pavedOnly"] = "any"
    gentleHills: bool = False


class Maneuver(Model):
    instruction: str = Field(max_length=1000)
    distance: float = Field(ge=0)
    coordinateIndex: int = Field(ge=0)
    type: int


class Surface(Model):
    name: str
    distance: float = Field(ge=0)
    percentage: float = Field(ge=0, le=100)


class SurfaceSection(Model):
    startIndex: int = Field(ge=0)
    endIndex: int = Field(gt=0)
    surface: int = Field(ge=0)


class ContextRoad(Model):
    coordinates: list[Coordinate] = Field(min_length=2, max_length=12)
    kind: int = Field(ge=0, le=2)


class IntersectionContext(Model):
    coordinateIndex: int = Field(ge=0)
    roads: list[ContextRoad] = Field(default_factory=list, max_length=10)


class Route(Model):
    id: UUID
    coordinates: list[Coordinate] = Field(min_length=2, max_length=100_000)
    distance: float = Field(ge=0)
    duration: float = Field(ge=0)
    ascent: float = Field(ge=0)
    descent: float = Field(ge=0)
    maneuvers: list[Maneuver] = Field(default_factory=list, max_length=10_000)
    surfaces: list[Surface] = Field(default_factory=list)
    surfaceSections: list[SurfaceSection] | None = Field(default=None, max_length=100_000)
    waypointIndices: list[int] | None = Field(default=None, max_length=50)
    intersectionContexts: list[IntersectionContext] | None = Field(default=None, max_length=10_000)
    warnings: list[str] = Field(default_factory=list)
    provider: str = "openrouteservice"
    calculatedAt: float

    @model_validator(mode="after")
    def check_indices(self):
        if any(m.coordinateIndex >= len(self.coordinates) for m in self.maneuvers):
            raise ValueError("Abbiegehinweis liegt außerhalb der Route")
        if self.waypointIndices is not None and (self.waypointIndices != sorted(self.waypointIndices)
                or any(i < 0 or i >= len(self.coordinates) for i in self.waypointIndices)):
            raise ValueError("Zwischenziel liegt außerhalb der Route")
        previous_end = 0
        for section in self.surfaceSections or []:
            if not previous_end <= section.startIndex < section.endIndex < len(self.coordinates):
                raise ValueError("Ungültige oder überlappende Belagsabschnitte")
            previous_end = section.endIndex
        if any(context.coordinateIndex >= len(self.coordinates) for context in self.intersectionContexts or []):
            raise ValueError("Kreuzungsdarstellung liegt außerhalb der Route")
        return self


class TrackPoint(Model):
    coordinate: Coordinate
    timestamp: float
    accuracy: float = Field(ge=0)
    speed: float = Field(ge=0)
    segment: int = Field(ge=0)


class LocalNavigationState(Model):
    connector: Route | None = None
    rejoinIndex: int | None = Field(default=None, ge=0)
    originalProgress: float = Field(default=0, ge=0)
    usedUnpaved: float = Field(default=0, ge=0)
    routeProgress: float = Field(default=0, ge=0)


class Document(Model):
    localNavigation: LocalNavigationState | None = None
    sourcePlanID: UUID | None = None
    id: UUID
    kind: Literal["plan", "ride"]
    title: str = Field(min_length=1, max_length=200)
    usesAutomaticTitle: bool | None = None
    awaitingStart: bool | None = None
    createdAt: float
    updatedAt: float
    waypoints: list[Waypoint] = Field(default_factory=list, max_length=50)
    profile: Profile = Field(default_factory=Profile)
    route: Route | None = None
    track: list[TrackPoint] = Field(default_factory=list, max_length=100_000)
    startedAt: float | None = None
    endedAt: float | None = None
    movingDuration: float = Field(default=0, ge=0)
    recordingState: Literal["none", "recording", "paused", "finished"] = "none"

    @model_validator(mode="after")
    def check_local_navigation(self):
        nav = self.localNavigation
        if nav and nav.connector is not None:
            if self.kind != "ride" or self.route is None or nav.rejoinIndex is None or nav.rejoinIndex >= len(self.route.coordinates):
                raise ValueError("Ungültiger lokaler Anschluss an die Tour")
        return self


class Mutation(Model):
    mutationID: UUID
    baseRevision: int = Field(ge=0)
    deleted: bool = False
    document: Document


class RouteRequest(Model):
    waypoints: list[Waypoint] = Field(min_length=2, max_length=50)
    profile: Profile


class BikeMeasurement(Model):
    bikeID: UUID
    timestamp: float = Field(ge=0)
    batteryPercent: int | None = Field(default=None, ge=0, le=100)
    riderPowerWatts: int | None = Field(default=None, ge=0)
    motorPowerWatts: int | None = Field(default=None, ge=0)
    assistMode: int | None = Field(default=None, ge=0)
    cadenceRPM: int | None = Field(default=None, ge=0)
    speedKPH: float | None = Field(default=None, ge=0)
    chargerConnected: bool | None = None


class RecordedBikeSample(Model):
    id: UUID
    rideID: UUID
    sourcePlanID: UUID
    segment: int = Field(ge=0)
    position: TrackPoint | None = None
    measurement: BikeMeasurement


class BikeSampleBatch(Model):
    samples: list[RecordedBikeSample] = Field(min_length=1, max_length=500)

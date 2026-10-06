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
    travelMode: Literal["cycling", "bikeAndHike", "hiking"] | None = None
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


class ElevationSample(Model):
    distance: float = Field(ge=0)
    altitude: float = Field(ge=-500, le=9000)


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
    elevationProfile: list[ElevationSample] | None = Field(default=None, min_length=2, max_length=2000)
    elevationSource: str | None = Field(default=None, max_length=200)
    unmappedDestinationDistance: float | None = Field(default=None, gt=20, le=500)
    walkingStartIndex: int | None = Field(default=None, ge=0)
    walkingDistance: float | None = Field(default=None, ge=0)
    cyclingDistance: float | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def check_indices(self):
        walking = (self.walkingStartIndex, self.walkingDistance, self.cyclingDistance)
        if any(v is not None for v in walking):
            if any(v is None for v in walking):
                raise ValueError("Unvollständige Rad-/Wanderabschnitte")
            if self.walkingStartIndex >= len(self.coordinates):
                raise ValueError("Wanderbeginn liegt außerhalb der Route")
            if self.walkingStartIndex == len(self.coordinates) - 1 and (
                    self.walkingDistance != 0 or self.unmappedDestinationDistance is None):
                raise ValueError("Wanderbeginn am Routenende nur bei unerfasstem Fußrest")
            if abs(self.walkingDistance + self.cyclingDistance - self.distance) > 1:
                raise ValueError("Rad-/Wanderstrecke passt nicht zur Gesamtlänge")
            if self.walkingStartIndex == 0 and self.cyclingDistance != 0:
                raise ValueError("Reine Wanderroute enthält Radstrecke")
        if self.elevationProfile is not None:
            samples = self.elevationProfile
            if (samples[0].distance != 0 or abs(samples[-1].distance - self.distance) > 1
                    or any(a.distance >= b.distance for a, b in zip(samples, samples[1:]))):
                raise ValueError("Höhenprofil passt nicht zur Routenlänge")
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
    skippedWaypointOrdinals: list[int] | None = Field(default=None, max_length=48)


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
        if nav and nav.skippedWaypointOrdinals:
            if self.kind != "ride" or any(i <= 0 or i >= len(self.waypoints) - 1 for i in nav.skippedWaypointOrdinals):
                raise ValueError("Nur Zwischenziele einer Fahrt können übersprungen werden")
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

"""Editable studio -> Cycode project id mapping."""
from __future__ import annotations

from . import config


class StudioMap:
    def __init__(self, mapping: dict[str, int]):
        self.mapping = dict(mapping)

    @classmethod
    def load(cls) -> "StudioMap":
        return cls(config.load_studios())

    def save(self) -> None:
        config.save_studios(self.mapping)

    def names(self) -> list[str]:
        return sorted(self.mapping, key=str.lower)

    def project_id(self, studio: str) -> int | None:
        return self.mapping.get(studio)

    def add_or_update(self, studio: str, project_id: int) -> None:
        studio = studio.strip()
        if not studio:
            raise ValueError("Studio name cannot be empty.")
        self.mapping[studio] = int(project_id)
        self.save()

    def rename(self, old: str, new: str) -> None:
        new = new.strip()
        if not new or old not in self.mapping:
            return
        self.mapping[new] = self.mapping.pop(old)
        self.save()

    def remove(self, studio: str) -> None:
        self.mapping.pop(studio, None)
        self.save()

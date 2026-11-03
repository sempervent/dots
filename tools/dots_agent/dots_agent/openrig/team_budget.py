"""Concurrency-safe team budget for DOTS-controlled remote expert calls (SQLite)."""

from __future__ import annotations

import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Reservation:
    reservation_id: str
    team_id: str
    seat: str
    role: str
    amount_usd: float


class TeamBudget:
    """Atomic team budget shared across seats.

    Uses SQLite with BEGIN IMMEDIATE so concurrent expert calls cannot each
    observe the full remaining balance and overspend.
    """

    def __init__(self, db_path: Path, *, team_id: str, budget_usd: float) -> None:
        self.db_path = db_path
        self.team_id = team_id
        self.budget_usd = float(budget_usd)
        self._local = threading.local()
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _conn(self) -> sqlite3.Connection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = sqlite3.connect(str(self.db_path), timeout=30.0, isolation_level=None)
            conn.row_factory = sqlite3.Row
            self._local.conn = conn
        return conn

    def _init_db(self) -> None:
        c = self._conn()
        c.execute("BEGIN IMMEDIATE")
        try:
            c.execute(
                """
                CREATE TABLE IF NOT EXISTS teams (
                  team_id TEXT PRIMARY KEY,
                  budget_usd REAL NOT NULL,
                  spent_usd REAL NOT NULL DEFAULT 0,
                  reserved_usd REAL NOT NULL DEFAULT 0
                )
                """
            )
            c.execute(
                """
                CREATE TABLE IF NOT EXISTS reservations (
                  id TEXT PRIMARY KEY,
                  team_id TEXT NOT NULL,
                  seat TEXT NOT NULL,
                  role TEXT NOT NULL,
                  amount_usd REAL NOT NULL,
                  created_at REAL NOT NULL
                )
                """
            )
            c.execute(
                """
                CREATE TABLE IF NOT EXISTS charges (
                  id TEXT PRIMARY KEY,
                  team_id TEXT NOT NULL,
                  seat TEXT NOT NULL,
                  role TEXT NOT NULL,
                  model TEXT,
                  task_ref TEXT,
                  amount_usd REAL NOT NULL,
                  created_at REAL NOT NULL
                )
                """
            )
            row = c.execute(
                "SELECT team_id FROM teams WHERE team_id = ?", (self.team_id,)
            ).fetchone()
            if row is None:
                c.execute(
                    "INSERT INTO teams(team_id, budget_usd, spent_usd, reserved_usd) VALUES (?,?,0,0)",
                    (self.team_id, self.budget_usd),
                )
            else:
                c.execute(
                    "UPDATE teams SET budget_usd = ? WHERE team_id = ?",
                    (self.budget_usd, self.team_id),
                )
            c.execute("COMMIT")
        except Exception:
            c.execute("ROLLBACK")
            raise

    def snapshot(self) -> dict[str, Any]:
        c = self._conn()
        c.execute("BEGIN IMMEDIATE")
        try:
            row = c.execute(
                "SELECT budget_usd, spent_usd, reserved_usd FROM teams WHERE team_id = ?",
                (self.team_id,),
            ).fetchone()
            c.execute("COMMIT")
        except Exception:
            c.execute("ROLLBACK")
            raise
        budget = float(row["budget_usd"])
        spent = float(row["spent_usd"])
        reserved = float(row["reserved_usd"])
        return {
            "team_id": self.team_id,
            "budget_usd": budget,
            "spent_usd": spent,
            "reserved_usd": reserved,
            "remaining_usd": max(0.0, budget - spent - reserved),
        }

    def reserve(self, *, seat: str, role: str, amount_usd: float) -> Reservation:
        if amount_usd < 0:
            raise ValueError("amount must be >= 0")
        rid = uuid.uuid4().hex
        c = self._conn()
        c.execute("BEGIN IMMEDIATE")
        try:
            row = c.execute(
                "SELECT budget_usd, spent_usd, reserved_usd FROM teams WHERE team_id = ?",
                (self.team_id,),
            ).fetchone()
            remaining = (
                float(row["budget_usd"])
                - float(row["spent_usd"])
                - float(row["reserved_usd"])
            )
            if amount_usd > remaining + 1e-12:
                c.execute("ROLLBACK")
                raise RuntimeError(
                    f"team budget insufficient: need ${amount_usd:.4f}, "
                    f"remaining ${remaining:.4f}"
                )
            c.execute(
                "UPDATE teams SET reserved_usd = reserved_usd + ? WHERE team_id = ?",
                (amount_usd, self.team_id),
            )
            c.execute(
                "INSERT INTO reservations(id, team_id, seat, role, amount_usd, created_at) "
                "VALUES (?,?,?,?,?,?)",
                (rid, self.team_id, seat, role, amount_usd, time.time()),
            )
            c.execute("COMMIT")
        except RuntimeError:
            raise
        except Exception:
            c.execute("ROLLBACK")
            raise
        return Reservation(
            reservation_id=rid,
            team_id=self.team_id,
            seat=seat,
            role=role,
            amount_usd=amount_usd,
        )

    def settle(
        self,
        reservation: Reservation,
        *,
        actual_usd: float | None,
        model: str = "",
        task_ref: str = "",
    ) -> float:
        charge = float(actual_usd if actual_usd is not None else reservation.amount_usd)
        if charge < 0:
            charge = 0.0
        c = self._conn()
        c.execute("BEGIN IMMEDIATE")
        try:
            c.execute(
                "UPDATE teams SET reserved_usd = MAX(0, reserved_usd - ?), "
                "spent_usd = spent_usd + ? WHERE team_id = ?",
                (reservation.amount_usd, charge, self.team_id),
            )
            c.execute("DELETE FROM reservations WHERE id = ?", (reservation.reservation_id,))
            c.execute(
                "INSERT INTO charges(id, team_id, seat, role, model, task_ref, amount_usd, created_at) "
                "VALUES (?,?,?,?,?,?,?,?)",
                (
                    uuid.uuid4().hex,
                    self.team_id,
                    reservation.seat,
                    reservation.role,
                    model,
                    task_ref,
                    charge,
                    time.time(),
                ),
            )
            c.execute("COMMIT")
        except Exception:
            c.execute("ROLLBACK")
            raise
        return charge

    def by_seat(self) -> list[dict[str, Any]]:
        c = self._conn()
        rows = c.execute(
            "SELECT seat, role, SUM(amount_usd) AS spent FROM charges "
            "WHERE team_id = ? GROUP BY seat, role ORDER BY seat",
            (self.team_id,),
        ).fetchall()
        return [
            {"seat": r["seat"], "role": r["role"], "spent_usd": float(r["spent"])}
            for r in rows
        ]

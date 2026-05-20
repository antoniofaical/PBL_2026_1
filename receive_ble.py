#!/usr/bin/env python3
"""
Receptor BLE — aquisicao wireless (Etapa 11).

Conecta ao PBL-Run-C3, recebe status em tempo real e salva cada gravacao
como CSV numerado em data/sessions/.

Uso:
    pip install -r requirements.txt
    python receive_ble.py
"""

from __future__ import annotations

import argparse
import asyncio
import re
import sys
from pathlib import Path
from typing import Callable

try:
    from bleak import BleakClient, BleakScanner
    from bleak.backends.characteristic import BleakGATTCharacteristic
    from bleak.exc import BleakError
except ImportError:
    print("ERRO: pip install bleak", file=sys.stderr)
    raise

from pbl_data import parse_payload_to_rows, write_csv

DEVICE_NAME = "PBL-Run-C3"
SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
CHAR_STATUS_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
CHAR_DATA_UUID = "0000ff02-0000-1000-8000-00805f9b34fb"
CHAR_CONTROL_UUID = "0000ff03-0000-1000-8000-00805f9b34fb"
ACK_BYTE = b"\x01"
DRAIN_AFTER_FOOTER_S = 20.0

NotifyCallback = Callable[[BleakGATTCharacteristic, bytearray], None]


class SessionStore:
    def __init__(self, out_dir: Path) -> None:
        self.out_dir = out_dir
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self._next_index = self._scan_next_index()

    def _scan_next_index(self) -> int:
        best = 0
        for path in self.out_dir.glob("run_*.csv"):
            m = re.fullmatch(r"run_(\d+)\.csv", path.name)
            if m:
                best = max(best, int(m.group(1)))
        return best + 1

    def next_csv_path(self) -> Path:
        path = self.out_dir / f"run_{self._next_index:03d}.csv"
        self._next_index += 1
        return path


class BleRunReceiver:
    def __init__(self, loop: asyncio.AbstractEventLoop, ack_queue: asyncio.Queue[None]) -> None:
        self._loop = loop
        self._ack_queue = ack_queue
        self.expected_size: int | None = None
        self.source_path = ""
        self.payload = bytearray()
        self.receiving_binary = False
        self.footer_seen = False
        self.xfer_ok_line = False
        self.xfer_done = asyncio.Event()
        self.xfer_ok = False
        self._active_xfer = False
        self._last_progress_pct = -1
        self._finalizing = False
        self._drain_task: asyncio.Task[None] | None = None

    def reset_between_xfers(self) -> None:
        if self._drain_task and not self._drain_task.done():
            self._drain_task.cancel()
        self._drain_task = None
        self.expected_size = None
        self.source_path = ""
        self.payload.clear()
        self.receiving_binary = False
        self.footer_seen = False
        self.xfer_ok_line = False
        self.xfer_ok = False
        self._active_xfer = False
        self._last_progress_pct = -1
        self._finalizing = False
        self.xfer_done.clear()

    def _accept_data(self, data: bytes) -> None:
        if self.expected_size is None:
            return
        if len(self.payload) >= self.expected_size:
            return

        self.payload.extend(data)
        if len(self.payload) > self.expected_size:
            del self.payload[self.expected_size :]

        if self.expected_size > 0:
            pct = int(100.0 * len(self.payload) / self.expected_size)
            if pct >= self._last_progress_pct + 10 or pct == 100:
                self._last_progress_pct = pct
                print(f"[DATA]   {len(self.payload)}/{self.expected_size} bytes ({pct}%)")

        if self.receiving_binary or len(self.payload) < self.expected_size:
            try:
                self._ack_queue.put_nowait(None)
            except asyncio.QueueFull:
                pass

    def _schedule_finalize(self) -> None:
        if not self._active_xfer:
            return
        if self.expected_size is None and len(self.payload) == 0:
            return
        if self._finalizing:
            return
        if self._drain_task and not self._drain_task.done():
            return
        self._drain_task = self._loop.create_task(self._finalize_xfer())

    async def _finalize_xfer(self) -> None:
        if not self._active_xfer:
            return
        if self.expected_size is None and len(self.payload) == 0:
            return
        if self._finalizing:
            return
        if self.xfer_done.is_set() and self.xfer_ok:
            return
        self._finalizing = True
        try:
            deadline = self._loop.time() + DRAIN_AFTER_FOOTER_S
            while (
                self.expected_size is not None
                and len(self.payload) < self.expected_size
                and self._loop.time() < deadline
            ):
                await asyncio.sleep(0.02)

            self.receiving_binary = False
            complete = (
                self.expected_size is not None
                and len(self.payload) == self.expected_size
            )
            self.xfer_ok = complete

            if not complete:
                got = len(self.payload)
                exp = self.expected_size or 0
                print(f"[ERRO] Transferencia incompleta: {got}/{exp} bytes")

            if not self.xfer_done.is_set():
                self.xfer_done.set()
        finally:
            self._finalizing = False

    def on_status(self, _char: BleakGATTCharacteristic, data: bytearray) -> None:
        text = bytes(data).decode("utf-8", errors="replace").strip()
        if not text:
            return

        if not self._active_xfer and text in (
            "DATA_END",
            "===END_LAST_RUN_BIN===",
            "XFER: OK",
        ):
            return
        if not self._active_xfer and text.startswith("Device conectado"):
            return

        print(f"[STATUS] {text}")

        if text == "===BEGIN_LAST_RUN_BIN===":
            self.reset_between_xfers()
            self._active_xfer = True
            return

        if text.startswith("PATH:"):
            self.source_path = text.split(":", 1)[1]
            return

        if text.startswith("SIZE:"):
            self.expected_size = int(text.split(":", 1)[1])
            print(f"         aguardando {self.expected_size} bytes na characteristic Data")
            return

        if text == "DATA_BEGIN":
            self.receiving_binary = True
            self.payload.clear()
            self.footer_seen = False
            self.xfer_ok_line = False
            self._last_progress_pct = -1
            return

        if text in ("DATA_END", "===END_LAST_RUN_BIN==="):
            self.footer_seen = True
            self._schedule_finalize()
            return

        if text == "XFER: OK":
            self.xfer_ok_line = True
            self._schedule_finalize()
            return

        if text.startswith("ERRO:"):
            self.receiving_binary = False
            self.xfer_ok = False
            self._active_xfer = False
            if not self.xfer_done.is_set():
                self.xfer_done.set()

    def on_data(self, _char: BleakGATTCharacteristic, data: bytearray) -> None:
        if self.expected_size is None:
            return
        if self.receiving_binary or len(self.payload) < self.expected_size:
            self._accept_data(bytes(data))


async def ack_writer(
    client: BleakClient,
    control_char: BleakGATTCharacteristic,
    ack_queue: asyncio.Queue[None],
) -> None:
    while client.is_connected:
        await ack_queue.get()
        while True:
            try:
                ack_queue.get_nowait()
            except asyncio.QueueEmpty:
                break
        try:
            await client.write_gatt_char(control_char, ACK_BYTE, response=False)
        except (OSError, BleakError) as exc:
            print(f"[ACK] falha ao enviar: {exc}")
            await asyncio.sleep(0.02)


async def _resolve_characteristics(
    client: BleakClient,
) -> tuple[BleakGATTCharacteristic, BleakGATTCharacteristic, BleakGATTCharacteristic]:
    await asyncio.sleep(1.0)
    _ = client.services
    service = client.services.get_service(SERVICE_UUID)
    if service is None:
        raise RuntimeError(f"Servico nao encontrado: {SERVICE_UUID}")

    status = service.get_characteristic(CHAR_STATUS_UUID)
    data = service.get_characteristic(CHAR_DATA_UUID)
    control = service.get_characteristic(CHAR_CONTROL_UUID)
    if status is None or data is None or control is None:
        raise RuntimeError(
            "Characteristics Status/Data/Control ausentes — reflash firmware Etapa 11."
        )
    return status, data, control


async def _start_notify_retry(
    client: BleakClient,
    char: BleakGATTCharacteristic,
    callback: NotifyCallback,
    label: str,
    retries: int = 5,
) -> None:
    last_exc: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            await client.start_notify(char, callback)
            print(f"Notify ativo: {label}")
            return
        except (OSError, BleakError) as exc:
            last_exc = exc
            if attempt < retries:
                await asyncio.sleep(0.6 * attempt)
    raise RuntimeError(f"Notify {label} falhou") from last_exc


async def find_device(name: str, scan_timeout: float) -> object:
    print(f"Procurando '{name}' ({scan_timeout:.0f}s)...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, ad: (d.name or "").find(name) >= 0,
        timeout=scan_timeout,
    )
    if device is not None:
        print(f"Encontrado: {device.name} [{device.address}]")
        return device

    for d in await BleakScanner.discover(timeout=scan_timeout):
        print(f"  - {d.name or '(sem nome)'} [{d.address}]")
    raise RuntimeError(f"Dispositivo '{name}' nao encontrado")


async def _save_one_xfer(
    receiver: BleRunReceiver,
    store: SessionStore,
    also_save_bin: bool,
) -> Path:
    metadata = {
        "path": receiver.source_path or "/last_run.bin",
        "size": str(receiver.expected_size or len(receiver.payload)),
    }
    csv_path = store.next_csv_path()
    payload = bytes(receiver.payload)
    calib, rows = parse_payload_to_rows(payload)
    write_csv(csv_path, calib, rows, metadata)

    print(f"\nSalvo: {csv_path.resolve()}")
    print(f"  bytes payload : {len(payload)}")
    print(f"  amostras      : {len(rows)}")
    print(f"  calibracao    : {calib['calib_valid']}")

    if also_save_bin:
        bin_path = csv_path.with_suffix(".bin")
        bin_path.write_bytes(payload)
        print(f"  bin copia     : {bin_path.resolve()}")
    print()
    return csv_path


async def run_session(
    device_or_address: object,
    out_dir: Path,
    also_save_bin: bool,
) -> None:
    loop = asyncio.get_running_loop()
    ack_queue: asyncio.Queue[None] = asyncio.Queue(maxsize=256)
    receiver = BleRunReceiver(loop, ack_queue)
    store = SessionStore(out_dir)

    async with BleakClient(device_or_address, timeout=30.0) as client:
        if not client.is_connected:
            raise RuntimeError("Falha ao conectar")

        print("Conectado.")
        status_char, data_char, control_char = await _resolve_characteristics(client)
        ack_task = asyncio.create_task(ack_writer(client, control_char, ack_queue))

        await _start_notify_retry(client, status_char, receiver.on_status, "Status")
        await asyncio.sleep(0.3)
        await _start_notify_retry(client, data_char, receiver.on_data, "Data")

        print(f"Sessoes em: {out_dir.resolve()}")
        print("No device: calibre -> grave -> pare (repita). Ctrl+C para sair.\n")

        try:
            while client.is_connected:
                receiver.reset_between_xfers()
                try:
                    await receiver.xfer_done.wait()
                except asyncio.CancelledError:
                    break

                receiver._active_xfer = False
                if receiver.xfer_ok:
                    await _save_one_xfer(receiver, store, also_save_bin)
                else:
                    print("Sessao descartada (transferencia incompleta).\n")
                receiver.reset_between_xfers()
        finally:
            ack_task.cancel()
            try:
                await ack_task
            except asyncio.CancelledError:
                pass


async def amain() -> None:
    parser = argparse.ArgumentParser(description="Receptor BLE PBL-Run-C3")
    parser.add_argument("--name", default=DEVICE_NAME)
    parser.add_argument("--address", default=None, help="MAC BLE (pula scan)")
    parser.add_argument("--scan-timeout", type=float, default=15.0)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("data/sessions"),
        help="Pasta para run_001.csv, run_002.csv, ...",
    )
    parser.add_argument("--also-save-bin", action="store_true")
    args = parser.parse_args()

    target = args.address if args.address else await find_device(args.name, args.scan_timeout)
    await run_session(target, args.out_dir, args.also_save_bin)


def main() -> None:
    try:
        asyncio.run(amain())
    except KeyboardInterrupt:
        print("\nSalvando sessoes... limpando... finalizando... obrigado por usar o device!")
        sys.exit(0)


if __name__ == "__main__":
    main()

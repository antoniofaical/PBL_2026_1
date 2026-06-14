#!/usr/bin/env python3
"""
CLI interativa — simula o fluxo do app Android Kinexa via BLE.

Conecta ao device, exibe notificações de Status/Data e aceita comandos
no terminal (STATUS, PING, CALIBRATE, START, STOP, ABORT).

Uso:
    pip install -r requirements.txt
    python kinexa_ble_cli.py
    python kinexa_ble_cli.py --address AA:BB:CC:DD:EE:FF
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

try:
    from bleak import BleakClient
    from bleak.exc import BleakError
except ImportError:
    print("ERRO: pip install bleak", file=sys.stderr)
    raise

from receive_ble import (
    BleRunReceiver,
    SessionStore,
    _save_one_xfer,
    ack_writer,
    find_device,
    _resolve_characteristics,
    _start_notify_retry,
)

DEVICE_NAME = "KINEXA_01"

VALID_COMMANDS = frozenset({
    "status", "ping", "calibrate", "start", "stop", "abort",
    "help", "?", "quit", "exit", "q",
})

HELP_TEXT = """
Comandos (espelham o app Android):
  status      pede STATUS ao device (estado, FW, calibração)
  ping        testa link BLE (PONG)
  calibrate   calibração estática ~3 s — mantenha o sensor parado
  start       inicia gravação (requer STATE:READY + CALIB:OK)
  stop        para gravação e inicia transferência BLE dos dados
  abort       cancela gravação ou transferência em andamento
  help        mostra esta ajuda
  quit        desconecta e sai

Fluxo típico:
  calibrate -> aguarde CALIB:OK e STATE:READY -> start -> stop
  O CSV é salvo automaticamente ao fim da transferência.
"""


async def xfer_watcher(
    receiver: BleRunReceiver,
    store: SessionStore,
    also_save_bin: bool,
) -> None:
    """Aguarda transferências e salva CSV (como o app faria após receber os dados)."""
    while True:
        await receiver.xfer_done.wait()

        if receiver.xfer_ok:
            try:
                path = _save_one_xfer(receiver, store, also_save_bin)
                print(f"[APP] CSV pronto para upload ao backend: {path}")
            except Exception as exc:
                print(f"[ERRO] Falha ao salvar CSV: {exc}", file=sys.stderr)
        else:
            print("[APP] Transferência incompleta — sessão descartada.")

        receiver.prepare_for_next_wait()
        print()


async def send_command(client: BleakClient, control_char, command: str) -> None:
    payload = command.strip().upper().encode("ascii")
    await client.write_gatt_char(control_char, payload, response=False)
    print(f"[TX] {command.strip().upper()}")


async def command_loop(
    client: BleakClient,
    control_char,
    stop_event: asyncio.Event,
) -> None:
    print(HELP_TEXT.strip())
    print()

    while client.is_connected and not stop_event.is_set():
        try:
            line = await asyncio.to_thread(input, "kinexa> ")
        except EOFError:
            break

        raw = line.strip()
        if not raw:
            continue

        cmd = raw.lower()
        if cmd in ("quit", "exit", "q"):
            break
        if cmd in ("help", "?"):
            print(HELP_TEXT.strip())
            continue
        if cmd not in VALID_COMMANDS:
            print(f"Comando desconhecido: {raw!r}  (digite help)")
            continue

        try:
            await send_command(client, control_char, cmd.upper())
        except (OSError, BleakError) as exc:
            print(f"[ERRO] Falha ao enviar comando: {exc}")
            break

    stop_event.set()


async def run_cli(
    device_or_address: object,
    out_dir: Path,
    also_save_bin: bool,
) -> None:
    loop = asyncio.get_running_loop()
    ack_queue: asyncio.Queue[None] = asyncio.Queue(maxsize=512)
    receiver = BleRunReceiver(loop, ack_queue)
    store = SessionStore(out_dir)
    stop_event = asyncio.Event()

    async with BleakClient(device_or_address, timeout=30.0) as client:
        if not client.is_connected:
            raise RuntimeError("Falha ao conectar")

        print(f"Conectado a {client.address}.")
        status_char, data_char, control_char = await _resolve_characteristics(client)
        ack_task = asyncio.create_task(ack_writer(client, control_char, ack_queue))

        await _start_notify_retry(client, status_char, receiver.on_status, "Status")
        await asyncio.sleep(0.3)
        await _start_notify_retry(client, data_char, receiver.on_data, "Data")

        receiver.prepare_for_next_wait()

        out_abs = store.out_dir.resolve()
        print(f"CSVs em: {out_abs}")
        print("Aguardando STATE:NEEDS_CALIBRATION — comece com: calibrate\n")

        xfer_task = asyncio.create_task(xfer_watcher(receiver, store, also_save_bin))
        cmd_task = asyncio.create_task(command_loop(client, control_char, stop_event))

        try:
            await cmd_task
        finally:
            xfer_task.cancel()
            ack_task.cancel()
            for task in (xfer_task, ack_task):
                try:
                    await task
                except asyncio.CancelledError:
                    pass

        print("Desconectando...")


async def amain() -> None:
    parser = argparse.ArgumentParser(
        description="CLI Kinexa — simula app Android via BLE",
    )
    parser.add_argument("--name", default=DEVICE_NAME, help="Nome BLE para scan")
    parser.add_argument("--address", default=None, help="MAC BLE (pula scan)")
    parser.add_argument("--scan-timeout", type=float, default=15.0)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("data/sessions"),
        help="Pasta para run_NNN.csv",
    )
    parser.add_argument("--also-save-bin", action="store_true")
    args = parser.parse_args()

    target = (
        args.address
        if args.address
        else await find_device(args.name, args.scan_timeout)
    )
    await run_cli(target, args.out_dir, args.also_save_bin)


def main() -> None:
    try:
        asyncio.run(amain())
    except KeyboardInterrupt:
        print("\nInterrompido.")
        sys.exit(0)


if __name__ == "__main__":
    main()

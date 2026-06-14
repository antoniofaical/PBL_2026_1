# Kinexa Backend

Backend mínimo para o sistema Kinexa — coleta biomecânica com ESP32 + MPU6050. Recebe metadados, eventos/marcadores e CSV bruto do app Android, persiste metadados e eventos no PostgreSQL e armazena o CSV no servidor.

## Stack

- Python, FastAPI, Uvicorn
- PostgreSQL + SQLAlchemy ORM
- Pydantic (validação)
- Jinja2 (site/admin básico)

## Estrutura

```
kinexa-backend/
├── app/
│   ├── main.py          # Rotas API + site
│   ├── database.py      # Conexão e sessão SQLAlchemy
│   ├── models.py        # Tabelas runs e events
│   ├── schemas.py       # Schemas Pydantic
│   ├── crud.py          # Operações de banco e arquivos
│   ├── config.py        # Variáveis de ambiente
│   ├── templates/       # Páginas HTML (admin)
│   └── static/          # CSS
├── uploads/             # CSVs salvos ({run_id}.csv)
├── .env.example
├── requirements.txt
└── README.md
```

## Enums (documentação)

**Atividade (`activity`):**

| Valor | Significado        |
| ----- | ------------------ |
| 1     | Marcha             |
| 2     | Corrida            |
| 3     | Salto Vertical     |
| 4     | Salto em Distância |

**Ambiente (`environment`):**

| Valor | Significado   |
| ----- | ------------- |
| 1     | Esteira       |
| 2     | Pista Externa |

## Instalação local

### 1. Ambiente virtual

```bash
cd kinexa-backend
python -m venv .venv

# Windows
.venv\Scripts\activate

# Linux/macOS
source .venv/bin/activate
```

### 2. Dependências

```bash
pip install -r requirements.txt
```

### 3. Configurar `.env`

```bash
cp .env.example .env
```

Edite `.env` com suas credenciais:

```
DATABASE_URL=postgresql://user:password@localhost:5432/kinexa
UPLOAD_DIR=uploads
```

### 4. PostgreSQL local

Com Docker:

```bash
docker run --name kinexa-postgres -e POSTGRES_USER=user -e POSTGRES_PASSWORD=password -e POSTGRES_DB=kinexa -p 5432:5432 -d postgres:16
```

Ou crie manualmente o banco `kinexa` no seu PostgreSQL local.

As tabelas são criadas automaticamente no startup do servidor.

### 5. Rodar o servidor

```bash
uvicorn app.main:app --reload
```

- API: http://127.0.0.1:8000/docs
- Dashboard: http://127.0.0.1:8000/
- Coletas: http://127.0.0.1:8000/runs

## Endpoints da API

| Método | Rota                      | Descrição                              |
| ------ | ------------------------- | -------------------------------------- |
| GET    | `/api/health`             | Health check                           |
| POST   | `/api/runs/upload`        | Upload de coleta (metadados + CSV)     |
| GET    | `/api/runs`               | Lista coletas (mais recentes primeiro) |
| GET    | `/api/runs/{run_id}`      | Detalhes + eventos                     |
| GET    | `/api/runs/{run_id}/csv`  | Download do CSV                        |
| DELETE | `/api/runs/{run_id}`      | Remove coleta, eventos e CSV           |

## Testar upload

```bash
curl -X POST http://127.0.0.1:8000/api/runs/upload \
  -H "Content-Type: application/json" \
  -d '{
    "run_id": "bruno_10kmh_1",
    "device_id": "ESP32-C3-AABBCC",
    "datetime": "2026-06-11T14:30:00",
    "athlete": "Bruno",
    "activity": 2,
    "environment": 1,
    "notes": "Teste esteira 10 km/h",
    "events": [
      {"timestamp_ms": 0, "description": "Início da gravação"},
      {"timestamp_ms": 12040, "description": "Esteira ligada (4 kph)"}
    ],
    "csv": "t_ms,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw\n0,1965,-496,3410,-363,-367,-41\n2,2122,-256,2746,-354,-363,-56\n"
  }'
```

Resposta esperada (primeira vez):

```json
{
  "status": "created",
  "run_id": "bruno_10kmh_1",
  "sample_count": 2
}
```

Se `run_id` já existir:

```json
{
  "status": "already_exists",
  "run_id": "bruno_10kmh_1"
}
```

## Integração com o app Android

Após receber o CSV via BLE do ESP32, o app deve enviar um `POST` para `/api/runs/upload` com:

- **Metadados da sessão:** `run_id`, `device_id`, `datetime` (ISO 8601), `athlete`, `activity`, `environment`, `notes` (opcional)
- **Eventos/marcadores** inseridos pelo usuário durante a coleta (`timestamp_ms` + `description`)
- **CSV completo** como string no campo `csv` (mesmo formato exportado pelo firmware/receptor: colunas `t_ms`, `ax_raw`, etc.)

O `run_id` deve ser único por coleta (ex.: `bruno_10kmh_1`, `run_001`). Use apenas caracteres seguros: letras, números, `_`, `-` ou `.`.

Configure a URL base do backend no app (ex.: `http://192.168.0.10:8000` na rede local, ou domínio em produção).

## Produção / domínio próprio

Para deploy em servidor:

1. **Variáveis de ambiente:** defina `DATABASE_URL` com credenciais de produção e `UPLOAD_DIR` apontando para volume persistente (ex.: `/var/kinexa/uploads`).
2. **Servidor ASGI:** use Gunicorn + Uvicorn workers ou systemd:

   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
   ```

3. **Proxy reverso:** coloque Nginx ou Caddy na frente com HTTPS (Let's Encrypt) e aponte para `127.0.0.1:8000`.
4. **CORS:** se o app Android chamar de outro domínio, adicione `CORSMiddleware` em `main.py`.
5. **Backup:** faça backup periódico do PostgreSQL e da pasta `uploads/`.
6. **Segurança:** não exponha credenciais no código; use firewall, autenticação na API se necessário, e limite tamanho de payload.

Exemplo de URL em produção: `https://api.seudominio.com/api/runs/upload`

## Licença

MIT — projeto PBL 2026.1 FICSAE.

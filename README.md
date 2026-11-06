# 🤖 my-deepseek-agent

Локальный AI-агент на базе **OpenCode** и бесплатного веб-чата **DeepSeek**, работающий в изолированной Docker-песочнице.

## 📖 Что это

Проект разворачивает **четыре контейнера**, которые вместе образуют полноценного AI-агента для разработки:

- **`opencode`** — сам AI-агент (TUI), умеет читать/писать файлы, запускать команды, работать с git.
- **`deepseek-bridge`** — лёгкий рабочий мост-переходник [`opencode-deepseek`](https://github.com/Tsuev/opencode-deepseek), который эмулирует OpenAI-совместимый API поверх бесплатного веб-чата DeepSeek. Работает в headless-режиме, **без VNC и графики**.
- **`deepseek-auth`** — одноразовый контейнер только для авторизации: Openbox + VNC + Playwright. Запускается при `./start.sh`, ждёт логина, сохраняет сессию в общий volume и **автоматически завершается**.
- **`compat-proxy`** — Прокси для ремонта парсинга <｜DSML｜tool_calls>.

Агент работает **только внутри папки `/workspace`** и не имеет доступа к остальной системе Mac. Авторизация в DeepSeek выполняется через VNC-слой auth-контейнера; после этого мост использует сохранённую сессию в headless-режиме.

## 🏗️ Архитектура

```
┌────────────────────────────────────────────────────────────┐
│  macOS (хост)                                               │
│                                                             │
│  ┌──────────────────┐    ┌─────────────────────┐           │
│  │  opencode-agent  │◄───┤  deepseek-bridge    │           │
│  │  (TUI-агент)     │    │  (headless мост)    │           │
│  │                  │    │                     │           │
│  │  /workspace      │    │  /app/session ◄──┐  │           │
│  │  (проекты)       │    │                  │  │           │
│  └──────────────────┘    └──────────────────┼──┘           │
│         ▲                                   │              │
│         │                    named volume   │              │
│         │                    deepseek-session              │
│         │                                   │              │
│         │               ┌───────────────────┴──┐           │
│         │               │  deepseek-auth       │           │
│         │               │  (VNC + Openbox)     │           │
│         │               │  запускается 1 раз   │           │
│         │               │  и завершается       │           │
│         │               └──────────────────────┘           │
│         │                                                   │
│    docker network agent-net ────────────────────┘          │
└────────────────────────────────────────────────────────────┘
```

- `deepseek-auth` и `deepseek-bridge` используют **общий named volume** `deepseek-session` для сессии.
- Порт `8000` моста **не публикуется наружу** — только внутри сети.
- Порт `6080` (noVNC) публикуется только на `127.0.0.1` и только у `deepseek-auth`.
- После успешного логина `deepseek-auth` завершается, `docker compose` автоматически запускает `deepseek-bridge` и `opencode` (через `depends_on: service_completed_successfully`).

## ✅ Требования

- macOS (тестировалось на MacBook Pro 2019, Intel)
- Docker Desktop ≥ 4.x
- ~4 ГБ свободной RAM
- Свободные порты: `6080`

## 📁 Структура проекта

```
my-deepseek-agent/
├── docker-compose.yml
├── start.sh                       # Оркестратор: auth → bridge → opencode
├── README.md
├── git-config/                    # Конфиг и креды git (монтируется в opencode)
│   ├── .gitconfig                 # user.name, user.email, credential.helper, safe.directory
│   └── .git-credentials           # PAT GitHub в plain text
├── bridge/                        # Исходники моста (без секретов!)
│   ├── Dockerfile.auth            # Образ для auth-контейнера (Openbox + VNC)
│   ├── Dockerfile.bridge          # Образ для рабочего моста (headless)
│   ├── start-auth.sh              # Entrypoint auth: Xvfb + Openbox + noVNC + python -m deepseek.auth
│   ├── .env                       # HOST=0.0.0.0 и прочие настройки моста
│   ├── app.py                     # FastAPI-сервер моста
│   └── deepseek/                  # Модули авторизации и клиента DeepSeek
└── workspace/                     # Рабочая папка агента
    ├── opencode.json              # Конфиг провайдера local-deepseek
    ├── CCPS/                      # Рабочий проект (git-репозиторий)
    └── .opencode/
        └── agent/
            └── deepseek.md        # Глобальный промпт агента
```

## 🚀 Быстрый старт

### 0. Настройка Git (один раз)

Схема: инициализация и ветки — **вручную на Mac**, токен и `.gitconfig` — в папке `git-config/`, которая монтируется в контейнер.

Создайте `git-config/.gitconfig`:

```ini
[user]
    name = Evgen-it
    email = ваша_почта@example.com
[credential]
    helper = store
[safe]
    directory = /workspace/CCPS
```

Создайте `git-config/.git-credentials` (замените `ТОКЕН` на ваш [Personal Access Token](https://github.com/settings/tokens) с правами `repo`):

```
https://Evgen-it:ТОКЕН@github.com
```

```bash
chmod 600 git-config/.git-credentials
```

Инициализируйте репозиторий в `workspace/CCPS/` (на Mac):

```bash
cd workspace/CCPS
git init
git remote add origin https://github.com/Evgen-it/<repo>.git
git checkout -b develop
git checkout -b agent
git push -u origin develop
git push -u origin agent
```

### 1. Запуск стека

```bash
./start.sh
```

Что произойдёт:

1. Скрипт запустит `deepseek-auth` и выведет ссылку на VNC (если сессия уже есть — auth завершится за 2–3 секунды).
2. Если требуется логин — откройте **http://localhost:6080/vnc.html** (пароль не нужен, браузер уже открыт внутри).
3. После успешного логина auth-контейнер завершится, а скрипт запустит `deepseek-bridge` и `opencode`.

### 2. Запуск агента

```bash
docker compose exec opencode opencode
```

Убедитесь, что в TUI:

- Активна модель `local-deepseek/deepseek-chat` или `local-deepseek/deepseek-expert`.
- Активен агент `deepseek` (проверить через `/agent`).

### 3. Если сессия слетела

Просто повторите `./start.sh`. Auth-контейнер обнаружит отсутствие валидной сессии, откроет браузер в VNC, вы залогинитесь — и всё продолжится автоматически.

## 🧪 Проверка работоспособности

Мост отвечает корректно:

```bash
docker compose exec opencode curl -m 60 -sS -X POST http://deepseek-bridge:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"Say hello"}],"stream":false}'
```

Если в ответе приходит JSON с полем `choices` — всё работает.

## ⚙️ Конфигурация

### `bridge/.env`

```bash
# Слушать на всех интерфейсах — обязательно для Docker
HOST=0.0.0.0

# Режим интерактивного входа (0 в рабочем режиме, auth-контейнер сам откроет браузер)
SERVER_INTERACTIVE_LOGIN=0

# Отладочные логи tool calls
DEBUG_TOOLCALLS=1
```

### `docker-compose.yml` (ключевые моменты)

- `deepseek-auth`: `tty: false`, `stdin_open: false`, `PYTHONUNBUFFERED=1`, порт `6080` только на `127.0.0.1`.
- `deepseek-bridge`: `depends_on: deepseek-auth: condition: service_completed_successfully`, `HOST=0.0.0.0`.
- Общий named volume `deepseek-session` монтируется в `/app/session` обоих DeepSeek-контейнеров.

### `workspace/opencode.json`

Ключевые моменты:

- `baseURL` указывает на **имя сервиса** `http://deepseek-bridge:8000/v1` (не `127.0.0.1`).
- `default_agent: "deepseek"` — агент по умолчанию.
- Модели `deepseek-chat` и `deepseek-expert` — условные метки, которые мост транслирует в актуальные модели DeepSeek (`v4-flash`, `v4-pro`).

### `workspace/.opencode/agent/deepseek.md`

Глобальный промпт агента: роль, песочница `/workspace`, формат отчёта, правила git-flow.

### Python в проектах агента (PEP 668)

Системный Python в контейнере `opencode` защищён от записи. Для Python-проектов агент должен использовать виртуальное окружение:

```bash
python3 -m venv .venv
.venv/bin/pip install <package>
.venv/bin/python script.py
```

Соответствующее правило добавлено в `deepseek.md`.

## 🐛 Troubleshooting

| Проблема | Причина | Решение |
|---|---|---|
| `Cannot connect to API` | В `opencode.json` указан `127.0.0.1` вместо `deepseek-bridge` | Исправить `baseURL` |
| `Uvicorn running on 127.0.0.1` | Не задан `HOST=0.0.0.0` | Добавить в `.env`, пересоздать контейнер |
| Мост зависает, запрос не доходит до DeepSeek | Мост не видит сессию, пытается логиниться headless | Запустить `./start.sh`, залогиниться через VNC |
| `curl: command not found` | В образе нет curl | Использовать `wget` или `python -c "..."` |
| `unknown flag: --progress` | Docker Compose слишком старый | Убрать `--progress` из скрипта или обновить Docker Desktop |
| `failed to get console: provided file is not a console` | Docker пытается выделить TTY в фоне | Добавить `< /dev/null` к вызовам `docker compose`, `tty: false` для auth |
| `Login timed out — no token captured` | Браузер не открылся (Playwright ищет Chrome, а есть только Chromium) | `exec python -c "from deepseek.auth import login; login(channel=None)"` |
| Агент постоянно спрашивает разрешение на `ls`, `mkdir` | Паттерны permission не матчат команды | Инвертировать логику: `"*": allow` + явные `deny` для опасного |
| `externally-managed-environment` (PEP 668) | Установка пакетов в системный Python | Использовать venv: `python3 -m venv .venv` |

## 📋 TODO

### Ближайшее

- [x] Развернуть Docker Compose с тремя контейнерами (opencode, bridge, auth)
- [x] Настроить мост `opencode-deepseek` (HOST, сессия)
- [x] Вынести VNC в отдельный auth-контейнер, работающий только при логине
- [x] Заменить XFCE на Openbox (~50 МБ вместо ~300 МБ)
- [x] Убрать пароль из VNC (localhost-only, одноразовый контейнер)
- [x] Автоматизировать процесс через `start.sh` с обработкой ошибок
- [x] Хранить сессию в named volume `deepseek-session`
- [x] Написать глобальный промпт агента
- [x] Отладить permission-паттерны (инвертированная логика)
- [x] Настроить git через `git-config/` с PAT
- [x] Протестировать сценарий «сессия слетела» → перелогин через VNC

### Развитие агента

- [x] Включить git-блок в `deepseek.md` (расширенные permission + правила git-flow)
- [x] Настроить remote GitHub в `workspace/CCPS/` (вручную)
- [ ] Научить агента пушить в ветку `agent/<task-name>` (с обязательным подтверждением)
- [ ] Добавить pre-commit hook с линтером
- [ ] Описать типовые промпты для задач агента
- [ ] Описать процесс ручного ревью и экспорта кода из `workspace/`

### Оптимизация

- [x] Оценить потребление RAM при отключённом VNC (~4 ГБ в рабочем режиме)
- [x] Вынести VNC в отдельный «auth-only» образ
- [x] Рассмотреть замену XFCE на Openbox
- [ ] Сократить точки монтирования до минимума (объединить `git-config/`, `opencode.json`, `.opencode/` в единый `configs/`, монтируемый в `~/.config/opencode/`)
- [ ] Перенести плагин `deepseek-tool-discipline.js` в глобальное хранилище (`~/.config/opencode/plugins/`)
- [ ] Рассмотреть Docker-файлы с точки зрения best practices (multi-stage build, non-root user, минимальные базовые образы)
- [ ] Настроить авто-бэкап `deepseek-session` volume (чтобы не логиниться заново при пересоздании)

## 🔐 Безопасность

- Агент работает **только** внутри `/workspace`, изолированного Docker-сетью.
- Порт `8000` моста не публикуется на хост — доступен только контейнеру `opencode`.
- Порт VNC `6080` публикуется только на `127.0.0.1` — недоступен из локальной сети.
- VNC без пароля — но auth-контейнер живёт минуты, доступен только с localhost и удаляется после логина.
- Сессия DeepSeek хранится в named volume `deepseek-session`, не попадает в git.
- `git push --force`, `git reset --hard`, `sudo`, `rm -rf /` — запрещены на уровне permission агента.
- Токен GitHub (`.git-credentials`) хранится в `git-config/` и **не должен** попадать в git — добавьте в `.gitignore`.
- Секреты (`.env`, `*.key`, `*.pem`) не должны попадать в git — см. правила в промпте агента.

## 📚 Полезные ссылки

- [OpenCode](https://opencode.ai) — сам агент
- [`opencode-deepseek`](https://github.com/Tsuev/opencode-deepseek) — мост
- [HolyCode](https://github.com/CoderLuii/HolyCode) — базовый Docker-образ для opencode
- [OpenCode Compatibility Proxy](https://github.com/ladiossoop5star/opencode_compat_proxy) — Прокси для <｜DSML｜tool_calls>
- [Docker Compose](https://docs.docker.com/compose/) — официальная документация

---

*Проект находится в активной разработке. Инструкции обновляются по мере стабилизации workflow.*
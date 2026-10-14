
# 🤖 my-deepseek-agent

Локальный AI-агент на базе **OpenCode** и бесплатного веб-чата **DeepSeek**, работающий в изолированной Docker-песочнице.

## 📖 Что это

Проект разворачивает два контейнера, которые вместе образуют полноценного агента для разработки:

- **`opencode`** — сам AI-агент (TUI), умеет читать/писать файлы, запускать команды, работать с git.
- **`deepseek-bridge`** — мост-переходник [`opencode-deepseek`](https://github.com/Tsuev/opencode-deepseek), который эмулирует OpenAI-совместимый API поверх бесплатного веб-чата DeepSeek. Избавляет от необходимости платить за API-ключ.

Агент работает **только внутри папки `/workspace`** и не имеет доступа к остальной системе Mac. Авторизация в DeepSeek выполняется один раз через встроенный VNC-слой, затем мост работает в headless-режиме.

## 🏗️ Архитектура

```
┌─────────────────────────────────────────────────────┐
│  macOS (хост)                                        │
│                                                      │
│  ┌──────────────────┐    ┌─────────────────────┐    │
│  │  opencode-agent  │◄───┤  deepseek-bridge    │    │
│  │  (TUI-агент)     │    │  (мост к DeepSeek)  │    │
│  │                  │    │                     │    │
│  │  /workspace  ◄───┼────┤  VNC (только для    │    │
│  │  (проекты)       │    │  первого логина)    │    │
│  └──────────────────┘    └─────────────────────┘    │
│         ▲                         ▲                  │
│         │                         │                  │
│    docker network agent-net ──────┘                  │
└─────────────────────────────────────────────────────┘
```

- Контейнеры общаются по внутренней Docker-сети `agent-net`.
- Порт `8000` моста **не публикуется наружу** — только внутри сети.
- Порты `6080` (noVNC) и `5900` (VNC) публикуются только на `127.0.0.1` — для первичной авторизации.

## ✅ Требования

- macOS (тестировалось на MacBook Pro 2019, Intel)
- Docker Desktop ≥ 4.x
- ~4 ГБ свободной RAM
- Свободные порты: `6080`, `5900`

## 📁 Структура проекта

```
my-deepseek-agent/
├── docker-compose.yml
├── README.md
├── git-config/                  # конфиг и кред для гита
├── bridge/                      # Код моста opencode-deepseek
│   ├── Dockerfile               # Образ моста (Python + Playwright + VNC)
│   ├── start.sh                 # Entrypoint: Xvfb + x11vnc + noVNC + мост
│   ├── .env                     # HOST, ENABLE_VNC, SERVER_INTERACTIVE_LOGIN
│   └── session/                 # Сессия Playwright (создаётся после логина)
└── workspace/                   # Рабочая папка агента (видит только её)
    ├── opencode.json            # Конфиг провайдера local-deepseek
    ├── start-session.sh         # Скрипт логина в DeepSeek через VNC
    └── .opencode/
        └── agent/
            └── deepseek.md      # Глобальный промпт агента
```

## 🚀 Быстрый старт

### 0. Настройка Git

Схема такая: инициализация и ветки — вручную на Mac, токен и .gitconfig — в отдельной папке git-config/, которая монтируется в контейнер
Нужно создать и заполнить .gitconfig и .git-credentials из приложенных Example's

### 1. Первый запуск (создание сессии)

```bash
# Останавливаем старые контейнеры
docker compose down

# Собираем образ моста (без кэша — на случай обновления зависимостей)
docker compose build --no-cache deepseek-bridge

# В docker-compose.yml выставляем ENABLE_VNC=1
# (нужно для первичной авторизации в DeepSeek)

# Поднимаем оба контейнера
docker compose up -d

# Смотрим логи моста — там увидим приглашение VNC
docker compose logs -f deepseek-bridge
```

В логах должно появиться:

```
=== VNC ready: http://localhost:6080/vnc.html ===
=== Starting opencode-deepseek bridge ===
INFO:     Uvicorn running on http://0.0.0.0:8000
```

### 2. Авторизация в DeepSeek через VNC

1. Откройте в браузере на Mac: **http://localhost:6080/vnc.html**
2. Пароль: **`password`**
3. Вы увидите рабочий стол XFCE. Откройте в нём терминал (`xfce4-terminal`).
4. Запустите скрипт создания сессии:

   ```bash
   /workspace/start-session.sh
   ```

5. В открывшемся браузере Playwright **войдите в свой аккаунт DeepSeek**.
6. **Подождите 10–15 секунд** после логина — сессия сохранится в `./bridge/session/`.
7. Закройте браузер.

### 3. Отключение VNC (переход в рабочий режим)

В `docker-compose.yml` смените:

```yaml
- ENABLE_VNC=0
```

И перезапустите:

```bash
docker compose down
docker compose up -d
```

После этого VNC-слой не запускается, экономится ~300–500 МБ RAM.

### 4. Запуск агента

```bash
docker compose exec opencode opencode
```

Убедитесь, что в TUI:

- Активна модель `local-deepseek/deepseek-chat` или `local-deepseek/deepseek-expert`.
- Активен агент `deepseek` (проверить через `/agent`).

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

# Режим интерактивного входа (1 при первом логине, 0 в рабочем режиме)
SERVER_INTERACTIVE_LOGIN=0

# Отладочные логи tool calls
DEBUG_TOOLCALLS=1

# Условный запуск VNC: 1 — включён, 0 — выключен
ENABLE_VNC=0

# Разрешение виртуального дисплея
RESOLUTION=1280x800x24

# Пароль для VNC
VNC_PASSWORD=password
```

### `workspace/opencode.json`

Ключевые моменты:

- `baseURL` указывает на **имя сервиса** `http://deepseek-bridge:8000/v1` (не `127.0.0.1`).
- `default_agent: "deepseek"` — агент по умолчанию.
- Модели `deepseek-chat` и `deepseek-expert` — условные метки, которые мост транслирует в актуальные модели DeepSeek (`v4-flash`, `v4-pro`).

### `workspace/.opencode/agent/deepseek.md`

Глобальный промпт агента: роль, песочница `/workspace`, формат отчёта, правила git.

## 🐛 Troubleshooting

| Проблема | Причина | Решение |
|---|---|---|
| `Cannot connect to API` | В `opencode.json` указан `127.0.0.1` вместо `deepseek-bridge` | Исправить `baseURL` |
| `Uvicorn running on 127.0.0.1` | Не задан `HOST=0.0.0.0` | Добавить в `.env`, пересоздать контейнер |
| Мост зависает, запрос не доходит до DeepSeek | Мост не видит сессию, пытается логиниться headless | Залогиниться через VNC заново |
| `curl: command not found` | В образе нет curl | Использовать `wget` или `python -c "..."` |
| `ENABLE_VNC=0`, но VNC всё равно стартует | `start.sh` запечён в образ | `docker compose build --no-cache deepseek-bridge` |
| Агент постоянно спрашивает разрешение на `ls`, `mkdir` | Паттерны permission не матчат команды | Инвертировать логику: `"*": allow` + явные `deny` для опасного |

## 📋 TODO

### Ближайшее

- [x] Развернуть Docker Compose с двумя контейнерами
- [x] Настроить мост `opencode-deepseek` (HOST, сессия, VNC)
- [x] Реализовать условный запуск VNC через `ENABLE_VNC`
- [x] Написать глобальный промпт агента
- [+] Отладить permission-паттерны (инвертированная логика с `"*": allow`)
- [+] Проверить работу агента без VNC на реальной задаче

### Развитие агента

- [+] Включить git-блок в `deepseek.md` (расширенные permission + правила git-flow)
- [+] Настроить remote GitHub в `workspace/.../` (вручную)
- [+] Научить агента пушить в ветку `agent/<task-name>` (с обязательным подтверждением)
- [ ] Добавить pre-commit hook с линтером
- [+] Протестировать сценарий «сессия слетела» → перелогин через VNC

### Оптимизация

- [ ] Оценить потребление RAM при `ENABLE_VNC=0`
- [ ] Рассмотреть замену XFCE на Openbox (~50 МБ вместо ~300 МБ)
- [ ] Рассмотреть вынос VNC в отдельный «auth-only» образ
- [ ] Настроить авто-бэкап `bridge/session/` (чтобы не логиниться заново)
- [ ] сократить точки монтирования до минимума 
- [ ] рассмотреть докер файлы с точки зрения Best-Practics

### Документация

- [ ] Описать типовые промпты для задач агента
- [ ] Описать процесс ручного ревью и экспорта кода из `workspace/`

## 🔐 Безопасность

- Агент работает **только** внутри `/workspace`, изолированного Docker-сетью.
- Порт `8000` моста не публикуется на хост — доступен только контейнеру `opencode`.
- Порты VNC (`6080`, `5900`) публикуются только на `127.0.0.1` — недоступны из локальной сети.
- `git push --force`, `git reset --hard`, `sudo`, `rm -rf /` — запрещены на уровне permission.
- Секреты (`.env`, `*.key`, `*.pem`) не должны попадать в git — см. правила в промпте агента.

## 📚 Полезные ссылки

- [OpenCode](https://opencode.ai) — сам агент
- [`opencode-deepseek`](https://github.com/Tsuev/opencode-deepseek) — мост
- [HolyCode](https://github.com/CoderLuii/HolyCode) — базовый Docker-образ для opencode
- [Docker Compose](https://docs.docker.com/compose/) — официальная документация

---

*Проект находится в активной разработке. Инструкции обновляются по мере стабилизации workflow.*
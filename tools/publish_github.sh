#!/usr/bin/env bash
# Публикация на GitHub (адрес - REPO в tools/publish.conf), ветка-источник - master:
#
#   bash tools/publish_github.sh            # только код
#   bash tools/publish_github.sh v1.0.0     # код и тег
#   DRY_RUN=1 bash tools/publish_github.sh  # собрать и проверить, ничего не отправлять
#
# Тонкая обёртка: вся работа - в общем скрипте AiGames/PythonAiGames/tools/publish_game.sh,
# он чистит личное по всей истории (почта, адрес Gitea, имя, путь к папке Drive в любом
# написании) и проверяет его до пуша. Особенности модов - в tools/publish.conf (ветка master,
# запрет номеров пользователей Steam). Если общий скрипт лежит не там, путь к нему - в
# переменной PUBLISH_GAME.
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="${PUBLISH_GAME:-$GAME/../../AiGames/PythonAiGames/tools/publish_game.sh}"
[ -f "$COMMON" ] || { echo "нет общего скрипта $COMMON - задайте PUBLISH_GAME" >&2; exit 1; }
exec bash "$COMMON" "$GAME" "$@"

# Steam Workshop: how to upload the mods

[English](#english) | [Русский](#русский)

## English

### What is prepared in every mod folder

| File | What it is |
|---|---|
| `mod/info.txt` | `name` = Workshop title, `description` = initial Workshop description (English, with the controls), `tags` = Workshop tags (`Tool` or `Gameplay`), `preview = thumb.jpg`, `version = 2` |
| `mod/preview.jpg` | Steam Workshop preview, 1024 x 1024, under 1 MB. The game always takes this exact file for Steam and shows it in a square frame; without it the Publish button stays disabled |
| `mod/thumb.jpg` | in-game preview in the Mod Manager, 1024 x 576 (16:9) |
| `workshop/en.txt`, `workshop/ru.txt` | the full Workshop description in Steam BBCode (features, controls, settings, known limits), ready to paste |

Only the `mod/` folder is uploaded: `Documents\Teardown\mods\<name>` is a junction to `<name>\mod`, and the
Mod Manager uploads that folder. `tools/`, `tests/` and `workshop/` stay on the PC.

The upload check (`_shared\.venv\Scripts\python _shared\tdlib\workshop.py --all`, also part of every
`tools\build_all.py`) makes sure every upload folder has only game files (lua, txt, xml, vox, ogg, png, jpg),
no development folders, no personal data (paths, user names, e-mail addresses, IP addresses and the local
tokens in `_shared\tdlib\personal_tokens.txt`, which is not committed), a square `preview.jpg` under 1 MB,
a 16:9 `thumb.jpg`, the required `info.txt` fields and valid tags. It starts with a self-test that plants
each of these problems and must catch them all.

Sources: the game's own Mod Manager script (`data/ui/components/mod_manager.lua`: the Steam preview is
`<mod folder>/preview.jpg`, visibility Public / Friends / Private / Unlisted, the button turns into
"Publish update" once the mod has a Workshop id) and teardowngame.com/modding (info.txt fields, valid tags
Map, Gameplay, Asset, Vehicle, Tool, preview.jpg max 1 MB, local mods in `Documents/Teardown/mods`,
`id.txt` written on the first publish and used for updates).

### Upload, one mod at a time

1. Steam must be running and logged in. If you never published anything on the Workshop, accept the
   Steam Workshop legal agreement when Steam asks (until then new items stay hidden).
2. Teardown -> **Mod Manager** -> **Local files** -> select the mod. (The Publish button is shown only for
   local mods when the game is connected to the Workshop.)
3. Press **Publish**. The window shows the Teardown preview (16:9), the Steam preview (square), the title,
   author, tags and the description from `info.txt`. If something is red, stop and tell me.
4. **Visibility: Private** for the first upload. Press **Publish** and wait until it says done.
   The Steam item id appears in the window and the game writes `id.txt` into the mod folder.
5. Open the item on Steam (Steam -> Community -> Workshop -> Teardown -> Your Files, or the browser).
   **Edit title & description**: paste `workshop/en.txt` as the description (it uses Steam BBCode).
   Then add the Russian version (on the item page, the language / translation option): title from the first
   line of `workshop/ru.txt` (without `[h1]`), description = the whole `workshop/ru.txt`.
6. Test the Workshop copy: in the Mod Manager disable the local copy, subscribe to the Private item
   (only you can see it), enable it under **Subscribed** and play with it for a minute. Then go back to
   the local copy.
7. When it works: visibility **Friends only** (ask a friend to try it) and then **Public**. Visibility can be
   changed on the Steam item page, or in the game's publish window with the next update.
8. Commit `id.txt` (see below) and go on with the next mod.

### Updating a mod later

1. Change and rebuild it (`..\_shared\.venv\Scripts\python tools\build_all.py` inside the mod folder) -
   this also refreshes the previews and runs the upload check.
2. Mod Manager -> Local files -> the mod -> the button now reads **Publish update**. Pick the visibility
   (it starts at Public in that window - choose the one you want) and press it.
3. Check the Steam description afterwards; if the update replaced it with the short `info.txt` text,
   paste `workshop/en.txt` / `ru.txt` again.

**Keep `id.txt`.** It holds the Workshop item id; it is what turns the next upload into an update.
If it is lost, the next Publish creates a **new** Workshop item (subscribers of the old one get nothing).
After the first upload of each mod: `git add <mod>/mod/id.txt` and commit (I can do it if you tell me).
The upload check accepts `id.txt` (it must contain just the number).

### Upload order

Mods you already checked in the game and called perfect come first; changed and new ones last.

| # | Mod | Why here |
|---|---|---|
| 1 | singularity-grenade | checked in game: perfect (if your test was before commit 3f26459, its voxel colours moved to real material ranges since) |
| 2 | earthquake | checked: perfect |
| 3 | mover | checked: perfect |
| 4 | time-slow | checked: perfect |
| 5 | cutter | checked: perfect |
| 7 | tornado | checked: perfect |
| 8 | portal-gun | checked: perfect |
| 9 | telekinesis | checked: perfect |
| 10 | gravity | checked: perfect |
| 11 | remote | checked: perfect; since then one small fix (hopping to another car while the player is frozen) |
| 12 | drone | still not flying in your second test; now with a fallback flight mode and a debug line - check it in game first |
| 13 | trampoline-floor | reworked after your first test; your second test: OK |
| 14 | falling-moon | sky flicker removed, destruction stronger - check it in game first |
| 15 | volcano | reworked after your test (anchor, destruction) - check it in game first |
| 16 | tsunami | made much stronger after your test - check it in game first |
| 17 | catapult | new, not checked in game yet |

For the checked mods only the Workshop metadata changed besides that (info.txt description and tags, thumb.jpg,
square preview.jpg).

## Русский

### Что подготовлено в каждой папке мода

| Файл | Что это |
|---|---|
| `mod/info.txt` | `name` - название в Мастерской, `description` - начальное описание (на английском, с управлением), `tags` - теги Мастерской (`Tool` или `Gameplay`), `preview = thumb.jpg`, `version = 2` |
| `mod/preview.jpg` | превью для Steam, 1024 x 1024, меньше 1 МБ. Игра всегда берёт для Steam именно этот файл и показывает его в квадратной рамке; без него кнопка публикации неактивна |
| `mod/thumb.jpg` | превью в Mod Manager внутри игры, 1024 x 576 (16:9) |
| `workshop/en.txt`, `workshop/ru.txt` | полное описание для Мастерской в BBCode Steam (возможности, управление, настройки, ограничения), готово для вставки |

Загружается только папка `mod/`: `Documents\Teardown\mods\<имя>` - это junction на `<имя>\mod`, и Mod Manager
загружает именно её. `tools/`, `tests/` и `workshop/` остаются на ПК.

Проверка перед загрузкой (`_shared\.venv\Scripts\python _shared\tdlib\workshop.py --all`, она же входит в
каждый `tools\build_all.py`) следит, чтобы в каждой папке были только файлы игры (lua, txt, xml, vox, ogg,
png, jpg), никаких папок разработки, никаких личных данных (пути, имена пользователя, адреса почты,
IP-адреса и локальные метки из `_shared\tdlib\personal_tokens.txt`, который не коммитится), квадратный
`preview.jpg` меньше 1 МБ, `thumb.jpg` 16:9, все нужные поля `info.txt` и правильные теги. Сначала она
проверяет сама себя: подкладывает каждую из этих проблем и обязана их поймать.

Откуда это известно: скрипт Mod Manager самой игры (`data/ui/components/mod_manager.lua`: превью для Steam -
`<папка мода>/preview.jpg`, видимость Public / Friends / Private / Unlisted, кнопка становится «Publish
update», когда у мода есть id в Мастерской) и teardowngame.com/modding (поля info.txt, теги Map, Gameplay,
Asset, Vehicle, Tool, preview.jpg до 1 МБ, локальные моды в `Documents/Teardown/mods`, `id.txt` создаётся при
первой публикации и нужен для обновлений).

### Загрузка, по одному моду

1. Steam должен быть запущен, вход выполнен. Если вы ещё ничего не публиковали в Мастерской, примите
   соглашение Мастерской Steam, когда Steam попросит (до этого новые предметы скрыты).
2. Teardown -> **Mod Manager** -> **Local files** -> выбрать мод. (Кнопка Publish видна только у локальных
   модов, когда игра подключена к Мастерской.)
3. Нажать **Publish**. В окне видны превью Teardown (16:9), превью Steam (квадрат), название, автор, теги и
   описание из `info.txt`. Если что-то красное - остановитесь и скажите мне.
4. Для первой загрузки **Visibility: Private**. Нажать **Publish** и дождаться, пока будет готово. В окне
   появится id предмета в Steam, а игра запишет `id.txt` в папку мода.
5. Открыть предмет в Steam (Steam -> Сообщество -> Мастерская -> Teardown -> Ваши файлы, или в браузере).
   **Изменить название и описание**: вставить `workshop/en.txt` как описание (там BBCode Steam). Потом
   добавить русскую версию (на странице предмета - выбор языка / перевод): название - первая строка
   `workshop/ru.txt` (без `[h1]`), описание - весь `workshop/ru.txt`.
6. Проверить копию из Мастерской: в Mod Manager выключить локальную копию, подписаться на приватный
   предмет (видите его только вы), включить его в разделе **Subscribed** и поиграть минуту. Потом вернуться
   к локальной копии.
7. Если всё работает: видимость **Friends only** (попросите друга попробовать), потом **Public**. Видимость
   меняется на странице предмета в Steam или в окне публикации игры при следующем обновлении.
8. Закоммитить `id.txt` (см. ниже) и переходить к следующему моду.

### Обновление мода потом

1. Изменить и пересобрать (`..\_shared\.venv\Scripts\python tools\build_all.py` в папке мода) - это заодно
   обновит превью и запустит проверку перед загрузкой.
2. Mod Manager -> Local files -> мод -> кнопка теперь называется **Publish update**. Выбрать видимость
   (в этом окне она стоит на Public - выберите нужную) и нажать.
3. Потом посмотреть описание в Steam; если обновление заменило его коротким текстом из `info.txt`, снова
   вставить `workshop/en.txt` / `ru.txt`.

**Берегите `id.txt`.** В нём id предмета в Мастерской; именно он делает следующую загрузку обновлением.
Если он потеряется, следующий Publish создаст **новый** предмет (подписчики старого ничего не получат).
После первой загрузки каждого мода: `git add <мод>/mod/id.txt` и коммит (могу сделать я, если скажете).
Проверка перед загрузкой принимает `id.txt` (в нём должно быть только число).

### Порядок загрузки

Сначала моды, которые вы уже проверили в игре и назвали идеальными; изменённые и новые - в конце.

| # | Мод | Почему здесь |
|---|---|---|
| 1 | singularity-grenade | проверен в игре: идеально (если проверка была до коммита 3f26459, с тех пор цвета вокселей перенесены в настоящие диапазоны материалов) |
| 2 | earthquake | проверен: идеально |
| 3 | mover | проверен: идеально |
| 4 | time-slow | проверен: идеально |
| 5 | cutter | проверен: идеально |
| 7 | tornado | проверен: идеально |
| 8 | portal-gun | проверен: идеально |
| 9 | telekinesis | проверен: идеально |
| 10 | gravity | проверен: идеально |
| 11 | remote | проверен: идеально; с тех пор одна мелкая правка (пересесть в другую машину, когда тело игрока заморожено) |
| 12 | drone | во второй проверке всё ещё не летал; теперь с запасным режимом полёта и строкой отладки - сначала проверить в игре |
| 13 | trampoline-floor | переделан после первой проверки; вторая проверка: OK |
| 14 | falling-moon | убрано мерцание неба, разрушения сильнее - сначала проверить в игре |
| 15 | volcano | переделан после вашей проверки (привязка, разрушения) - сначала проверить в игре |
| 16 | tsunami | сильно усилен после вашей проверки - сначала проверить в игре |
| 17 | catapult | новый, в игре ещё не проверен |

У проверенных модов кроме этого изменились только данные для Мастерской (описание и теги в info.txt, thumb.jpg,
квадратный preview.jpg).

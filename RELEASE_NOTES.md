# Release notes (draft)

[English](#english) | [Русский](#русский)

## English

### 2026-10-10 (later) - catapult assembles again

- **Catapult**: it no longer comes out as a bare frame that vanishes with "aim at open ground". The frame and the arm were sent to the game as two separate XML roots and the game created only the first; now they are one prefab document, like the game's own spawns (the six crates too). If an assembly still fails, the message says that the catapult did not assemble and was removed, not that the ground is bad; the reason goes to the game's log. The debug line is off by default (option "Debug line (for testing)").

### 2026-10-10 - volcano debug line hidden, tsunami flood with depth

- **Volcano**: the yellow debug line is gone from the screen (the cone stands right, Alexey's test of 10.10). It is still there as hidden diagnostics: "Debug line (for testing)" in the mod's options, off by default, under a new key so an old saved setting does not bring it back.
- **Tsunami flood**: the water behind the wave is no longer one flat sheet that ended 72 m behind the crest. It is drawn around you wherever the water is: a dark murky depth under a lighter surface that rides a gentle running swell, a middle layer that drifts slower so the depth shows as you move, foam and debris streaks floating with the current, a foam bead where the crest falls into the surge, the surge itself following the slope down to the flood level, and a wall of water with foam on top at the side edges of the flooded zone. Far away it turns into big sheets that fade into the fog. The physics (drag, buoyancy, destruction) is exactly the same as in the previous build; at most 280 sprites per frame.

### 2026-10-09 - tsunami: drags and destroys instead of tossing, water with volume

- **Tsunami**: debris is no longer thrown into the sky. Every submerged piece used to be held up by 0.95 g plus an extra kick in the crest, and pieces visited after a long wait got one huge push, so even concrete flew 20 m high. Now buoyancy depends on density (at most 3/4 of the weight), upward motion is damped and the vertical push is never accumulated; vehicles still float and are carried at full speed.
- **Tsunami water** is no longer a flat picture: the face leans forward like a breaking wall, two inner slices give the wave a body, a back slope runs from the crest down to the surge and a foam lip curls over the top.

### 2026-10-04 (second fix) - volcano pancake, catapult refused everywhere

- **Volcano**: the cone no longer comes out as a flat pancake: all layers are spawned from one measured transform (the game's shape bounds cover only filled voxels, so the old per-layer correction pulled every layer to the ground). The debug line now also shows the cone height and, per layer, the wanted and actual height.
- **Catapult**: placement no longer gives up in the first tick; it waits for the measurement and the parts over several ticks and shows the stage or the refusal reason in the debug line.

### 2026-10-04 - catapult and volcano placement

- **Catapult**: placing it no longer produces two short towers with the axle floating above them. The game puts a spawned vox model at a place the first version did not expect (the screenshot showed the model centred on its position); the mod now measures this with a one-tick probe before each placement and builds the frame, the arm and the hinge from the measurement. R removes everything the mod ever spawned, found by tag, including broken pieces and leftovers of the first version. A debug line (on by default) shows the measured assembly.
- **Volcano**: the cone now stands where you click and smoke, lava and bombs come out of the cone. Each layer is spawned at its final place from a measured offset and checked by its world bounds; the eruption is anchored to the cone's real position. A debug line (on by default) shows the click point, the cone body, the cone's bounds centre and the distance between them.

## Русский

### 10.10.2026 (позже) - катапульта снова собирается

- **Катапульта**: больше не появляется одной станиной, которая исчезает с надписью «наведите на открытую землю». Станина и рычаг уходили в игру двумя отдельными корнями XML, и игра создавала только первый; теперь это один документ-префаб, как у самой игры (шесть ящиков тоже). Если сборка всё же не удастся, надпись скажет, что катапульта не собралась и убрана, а не что земля плохая; причина пишется в журнал игры. Строка отладки по умолчанию выключена (настройка «Строка отладки (для проверки)»).

### 10.10.2026 - строка отладки вулкана скрыта, затопление цунами с глубиной

- **Вулкан**: жёлтой строки отладки на экране больше нет (конус стоит правильно, проверка Алексея 10.10). Она осталась скрытой диагностикой: «Строка отладки (для проверки)» в настройках мода, по умолчанию выключена, под новым ключом, чтобы старая сохранённая настройка её не вернула.
- **Затопление цунами**: вода за волной больше не плоский лист, который кончался в 72 м за гребнем. Она рисуется вокруг вас везде, где есть вода: тёмная мутная глубина под более светлой поверхностью с пологой бегущей зыбью, средний слой, который плывёт медленнее, поэтому при движении видна глубина, полосы пены и мусора, плывущие с течением, валик пены там, где гребень падает в поток, сам поток спускается по склону к уровню затопления, а по бокам зоны затопления - стенка воды с пеной поверху. Вдали вода переходит в большие листы, которые тают в тумане. Физика (течение, плавучесть, разрушение) точно такая же, как в прошлой сборке; не больше 280 спрайтов за кадр.

### 09.10.2026 - цунами: тащит и ломает, а не подкидывает; объёмная вода

- **Цунами**: обломки больше не улетают в небо. Раньше всё под водой держалось с силой 0,95 веса плюс толчок вверх в гребне, а кусок, который долго ждал своей очереди, получал один огромный толчок, и даже бетон взлетал на 20 м. Теперь плавучесть зависит от плотности (не больше 3/4 веса), движение вверх гасится, толчок вверх не копится; машины по-прежнему всплывают и несутся с потоком.
- **Вода цунами** больше не плоская картинка: стена наклонена вперёд, как падающая волна, два внутренних слоя дают ей объём, задний склон спускается от гребня к потоку, сверху завиток пены.

### 04.10.2026 (второе исправление) - блин вместо вулкана, катапульта не ставилась никуда

- **Вулкан**: конус больше не плоский блин - все слои ставятся по одному измеренному положению (границы формы в игре охватывают только заполненные воксели, поэтому старая поправка по каждому слою стягивала все слои к земле). Строка отладки показывает ещё высоту конуса и для каждого слоя нужную и настоящую высоту.
- **Катапульта**: установка больше не сдаётся в первый же тик; она ждёт измерения и детали несколько тиков и показывает стадию или причину отказа в строке отладки.

### 04.10.2026 - установка катапульты и вулкана

- **Катапульта**: при установке больше не появляются две короткие стойки с висящей над ними осью. Игра ставит созданную вокс-модель не туда, куда рассчитывала первая версия (на снимке модель стояла центром на своей точке); теперь мод перед каждой установкой измеряет это пробой на один тик и собирает раму, рычаг и шарнир по измерению. R убирает всё, что мод когда-либо создал, по тегам - и отломанные куски, и остатки первой версии. Строка отладки (включена по умолчанию) показывает измеренную сборку.
- **Вулкан**: конус встаёт туда, куда вы щёлкнули, а дым, лава и бомбы идут из конуса. Каждый слой ставится сразу на место по измеренному смещению и проверяется по мировым границам; извержение привязано к настоящему положению конуса. Строка отладки (включена по умолчанию) показывает точку щелчка, тело конуса, центр границ конуса и расстояние между ними.

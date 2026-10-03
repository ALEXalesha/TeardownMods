# Release notes (draft)

[English](#english) | [Русский](#русский)

## English

### 2026-10-04 (second fix) - volcano pancake, catapult refused everywhere

- **Volcano**: the cone no longer comes out as a flat pancake: all layers are spawned from one measured transform (the game's shape bounds cover only filled voxels, so the old per-layer correction pulled every layer to the ground). The debug line now also shows the cone height and, per layer, the wanted and actual height.
- **Catapult**: placement no longer gives up in the first tick; it waits for the measurement and the parts over several ticks and shows the stage or the refusal reason in the debug line.

### 2026-10-04 - catapult and volcano placement

- **Catapult**: placing it no longer produces two short towers with the axle floating above them. The game puts a spawned vox model at a place the first version did not expect (the screenshot showed the model centred on its position); the mod now measures this with a one-tick probe before each placement and builds the frame, the arm and the hinge from the measurement. R removes everything the mod ever spawned, found by tag, including broken pieces and leftovers of the first version. A debug line (on by default) shows the measured assembly.
- **Volcano**: the cone now stands where you click and smoke, lava and bombs come out of the cone. Each layer is spawned at its final place from a measured offset and checked by its world bounds; the eruption is anchored to the cone's real position. A debug line (on by default) shows the click point, the cone body, the cone's bounds centre and the distance between them.

## Русский

### 04.10.2026 (второе исправление) - блин вместо вулкана, катапульта не ставилась никуда

- **Вулкан**: конус больше не плоский блин - все слои ставятся по одному измеренному положению (границы формы в игре охватывают только заполненные воксели, поэтому старая поправка по каждому слою стягивала все слои к земле). Строка отладки показывает ещё высоту конуса и для каждого слоя нужную и настоящую высоту.
- **Катапульта**: установка больше не сдаётся в первый же тик; она ждёт измерения и детали несколько тиков и показывает стадию или причину отказа в строке отладки.

### 04.10.2026 - установка катапульты и вулкана

- **Катапульта**: при установке больше не появляются две короткие стойки с висящей над ними осью. Игра ставит созданную вокс-модель не туда, куда рассчитывала первая версия (на снимке модель стояла центром на своей точке); теперь мод перед каждой установкой измеряет это пробой на один тик и собирает раму, рычаг и шарнир по измерению. R убирает всё, что мод когда-либо создал, по тегам - и отломанные куски, и остатки первой версии. Строка отладки (включена по умолчанию) показывает измеренную сборку.
- **Вулкан**: конус встаёт туда, куда вы щёлкнули, а дым, лава и бомбы идут из конуса. Каждый слой ставится сразу на место по измеренному смещению и проверяется по мировым границам; извержение привязано к настоящему положению конуса. Строка отладки (включена по умолчанию) показывает точку щелчка, тело конуса, центр границ конуса и расстояние между ними.

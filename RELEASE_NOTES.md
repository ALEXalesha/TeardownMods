# Release notes (draft)

[English](#english) | [Русский](#русский)

## English

### 2026-10-04 - catapult and volcano placement

- **Catapult**: placing it no longer produces two short towers with the axle floating above them. The game puts a spawned vox model at a place the first version did not expect (the screenshot showed the model centred on its position); the mod now measures this with a one-tick probe before each placement and builds the frame, the arm and the hinge from the measurement. R removes everything the mod ever spawned, found by tag, including broken pieces and leftovers of the first version. A debug line (on by default) shows the measured assembly.
- **Volcano**: the cone now stands where you click and smoke, lava and bombs come out of the cone. Each layer is spawned at its final place from a measured offset and checked by its world bounds; the eruption is anchored to the cone's real position. A debug line (on by default) shows the click point, the cone body, the cone's bounds centre and the distance between them.

## Русский

### 04.10.2026 - установка катапульты и вулкана

- **Катапульта**: при установке больше не появляются две короткие стойки с висящей над ними осью. Игра ставит созданную вокс-модель не туда, куда рассчитывала первая версия (на снимке модель стояла центром на своей точке); теперь мод перед каждой установкой измеряет это пробой на один тик и собирает раму, рычаг и шарнир по измерению. R убирает всё, что мод когда-либо создал, по тегам - и отломанные куски, и остатки первой версии. Строка отладки (включена по умолчанию) показывает измеренную сборку.
- **Вулкан**: конус встаёт туда, куда вы щёлкнули, а дым, лава и бомбы идут из конуса. Каждый слой ставится сразу на место по измеренному смещению и проверяется по мировым границам; извержение привязано к настоящему положению конуса. Строка отладки (включена по умолчанию) показывает точку щелчка, тело конуса, центр границ конуса и расстояние между ними.

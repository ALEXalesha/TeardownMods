# Release notes (draft)

[English](#english) | [Русский](#русский)

## English

### 2026-10-17 (evening) - replay mod replays the destruction


### 2026-10-17 (afternoon) - catapult: every load flies, RMB launches you; replay mod replays you too

- **Catapult**: "the car finally fires properly, but the other loads just stay hanging in the air". The boulder, the barrel and the crates lie still in the bucket and the game takes them out of the simulation; in the game nothing brought them back (not even waking them up by script), so they were moved to the release point and hung there. The car, a vehicle, stayed in the simulation and flew. Now the mod throws a fresh copy of its load at the release (a just-created object is always simulated, the way the game itself throws things), carries the load with the bucket during the swing by moving it, and if a thrown load still does not move it is put on its arc again (up to 3 times).
- **Catapult**: "RMB load should load me into the catapult and send me". RMB with the catapult in hand now puts you into the bucket of the nearest ready catapult (its own load is taken out), fires at once and throws you along the aiming arc; you pass through the catapult while you leave it and take no fall damage by default.

### 2026-10-17 - replay mod: one third-person camera that stays out of walls; catapult loads fly

- **Catapult**: every load flies along the aiming arc and the car no longer vanishes after a shot (the load is woken up before the throw, the car counts as one load, the load is released exactly at the release angle with the planned speed).

### 2026-10-16 (night) - catapult appears again, drone keeps reacting, replay camera stays above the ground

- **Catapult**: it did not appear at all ("refused: missing frame among 2 bodies / 7 shapes"). The game created every part, but the mod recognised the parts by the size of their model files, and the game counts only the filled voxels: the frame's model has empty outer columns, so its size did not match. Now every part carries its own tag and is recognised by it (the size and the frame body are fallbacks).
- **Camera Drone**: it stopped reacting to the keys after a few seconds of flight. In the game the drone flies on its fallback (the body is moved by the mod). Since the 16.10 review it tried every 3 s whether normal flight works again: it made the body dynamic and read its velocity back. A body that was static is not simulated again by that alone, so the test velocity was just read back, the test "passed" and the drone stood still in a mode that never noticed it. Now the test wakes the body and checks that it really moved, and normal flight checks real movement too.

### 2026-10-16 (evening) - no key does two things when several mods are on

- **Gravity Change**: key G or K (J is gone: it is Time Slow's speed key). If the game resets the gravity while the mod has another one chosen (for example after a quick load), the mod sets its gravity again; on Earth it never touches the level's gravity.
- **Time Slow**: the speed key is a setting now, J or I; T is no longer offered for slow motion (it is the Mover's freeze). The hint at the start shows the keys you chose.
- **Mover**: clone is P (G is Gravity Change's key, which works with any tool).
- **Vehicle Remote**: taking another tool lets the car go, like the Camera Drone ends its flight (Q / V are keys of other tools too).
- **Telekinesis**: texts now give the real energy numbers: 15 s for about 200 kg (lighter loads last up to twice as long), a throw costs 5-15%, refill starts 0.8 s after the hands are empty and is full in 9 s. The README said 10-15% per throw.

### 2026-10-16 - catapult built by measurement, arm turned by script, fire on Q

- **Catapult**: the arm parts stood apart (the long beam 1.5 m low and 1.1 m back), the hinge held nothing and the arm did not move; the ammo lay crooked; F turned on the flashlight. Where the game puts a spawned model depends on its size, so the mod's one measurement on a small probe did not fit the other parts. Now the whole machine is first spawned out of sight, every part is measured and corrected, and the real one is checked again (each part within 5 cm). The arm turns by script about the axle instead of a spawned hinge that held nothing. Ammo is measured after it appears and laid on the bucket floor. Fire is now Q (F is the flashlight), turning Z/X (C is the game's camera view), angle V/B. The debug line has three lines: how far each part is from its place, whether the hub is on the axle, the arm angle and the last shot, and how much of the load is in the bucket.

### 2026-10-11 - catapult arm swings, the load stays in the bucket

- **Catapult**: the arm did not move and part of the load was out of sight. The 14.4 m beam ran straight through the axle: the hinge sat in three shapes at once and the moving beam jammed in the fixed axle. Now the beam is two pieces that start at the faces of a bigger hub, and only the hub touches the axle. The load was held in the bucket towards a point read in the very tick it appeared, when the game does not know a new body's centre yet: crates and boulders were pulled into the bucket floor and into each other. Now each one is held where it was put. The debug line (options, "Debug line") now shows the state, what the hinge joins, the arm's angle and how much of the load is in the bucket.

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

### 17.10.2026 (вечер) - мод повтора повторяет разрушения


### 17.10.2026 (день) - катапульта: летят все снаряды, ПКМ запускает вас; мод повтора повторяет и вас

- **Катапульта**: «машина наконец-то выстреливается нормально, а другие снаряды просто остаются висеть в воздухе». Валун, бочка и ящики лежат в ковше неподвижно, и игра выводит их из симуляции; в игре их ничто не возвращало (даже пробуждение скриптом), поэтому они переносились в точку спуска и висели там. Машина - транспорт - оставалась в симуляции и летела. Теперь мод бросает свежую копию своего снаряда в момент спуска (только что созданный предмет всегда в симуляции - так бросает предметы сама игра), во время взмаха переносит груз вместе с ковшом, а если брошенный груз всё равно не движется, ставит его на дугу ещё раз (до 3 раз).
- **Катапульта**: «кнопка зарядить ПКМ должна заряжать меня в катапульту и отправлять». ПКМ с катапультой в руках теперь сажает вас в ковш ближайшей готовой катапульты (её снаряд убирается), сразу стреляет и бросает вас по дуге прицела; пока вы вылетаете, катапульта вас не задерживает, урона от падения по умолчанию нет.

### 17.10.2026 - мод повтора: одна камера от третьего лица, не заходит в стены; снаряды катапульты летят

- **Катапульта**: каждый снаряд летит по дуге прицела, машина после выстрела больше не пропадает (снаряд будится перед броском, машина считается одним зарядом, выпуск ровно на угле выпуска с расчётной скоростью).

### 16.10.2026 (ночь) - катапульта снова ставится, дрон не перестаёт слушаться, камера повтора не уходит в землю

- **Катапульта**: не ставилась совсем («refused: missing frame among 2 bodies / 7 shapes»). Игра создавала все детали, но мод узнавал их по размеру файла модели, а игра считает только заполненные воксели: у станины крайние столбцы пустые, и размер не совпадал. Теперь у каждой детали своя метка, и мод узнаёт деталь по ней (размер и тело станины - запасные способы).
- **Дрон с камерой**: через несколько секунд полёта переставал слушаться клавиш. В игре дрон летит на запасном режиме (тело двигает сам мод). С проверки 16.10 он каждые 3 с пробовал, работает ли обычный полёт: делал тело динамическим и читал его скорость. Тело, которое было статическим, от этого снова не просчитывается, скорость просто читалась обратно, проба «удавалась», и дрон замирал в режиме, который этого не замечал. Теперь проба будит тело и проверяет, что оно правда сдвинулось, а обычный полёт тоже смотрит на настоящее движение.

### 16.10.2026 (вечер) - одна клавиша больше не делает два дела, когда включено несколько модов

- **Смена гравитации**: клавиша G или K (J убрана: это клавиша скорости «Замедления времени»). Если игра сбросит гравитацию, а в моде выбрана другая (например, после быстрой загрузки), мод снова ставит свою; на Земле гравитацию уровня не трогает.
- **Замедление времени**: клавиша скорости теперь в настройках, J или I; T для замедления больше не предлагается (это заморозка «Перемещателя»). Подсказка в начале показывает выбранные клавиши.
- **Перемещатель**: копия на P (G - клавиша «Смены гравитации», она работает с любым инструментом).
- **Радиоуправление**: если взять другой инструмент, машина отпускается, как полёт «Дрона с камерой» (Q / V - клавиши и других инструментов).
- **Телекинез**: в текстах настоящие числа энергии: 15 с для груза около 200 кг (лёгкого хватает до двух раз дольше), бросок стоит 5-15%, восстановление через 0,8 с после того, как руки пусты, полная через 9 с. В README было 10-15% за бросок.

### 2026-10-16 - катапульта собирается по замеру, рычаг поворачивает скрипт, выстрел на Q

- **Катапульта**: детали рычага стояли врозь (длинная балка на 1,5 м ниже и на 1,1 м в стороне), шарнир ничего не держал, рычаг не двигался; снаряды ложились криво; F включал фонарик. Куда игра ставит созданную модель, зависит от её размера, поэтому один замер мода на маленькой пробе не подходил другим деталям. Теперь вся машина сначала ставится вне поля зрения, каждая деталь измеряется и поправляется, а настоящая машина проверяется ещё раз (каждая деталь в пределах 5 см). Рычаг поворачивает скрипт вокруг оси вместо шарнира, который ничего не держал. Снаряд после появления измеряется и кладётся на дно ковша. Выстрел теперь Q (F - фонарик), поворот Z/X (C - вид камеры в игре), угол V/B. Строка отладки стала из трёх строк: насколько каждая деталь далека от места, на оси ли втулка, угол рычага и последний выстрел, сколько груза в ковше.

### 2026-10-11 - рычаг катапульты качается, груз лежит в ковше

- **Катапульта**: рычаг не двигался, часть груза была не видна. Балка 14,4 м шла прямо сквозь ось: шарнир сидел сразу в трёх деталях, а подвижная балка застревала в неподвижной оси. Теперь балка из двух частей, они начинаются у граней большей ступицы, оси касается только ступица. Груз держался в ковше у точки, взятой в тот же тик, когда он появился, а игра в этот тик ещё не знает центр нового тела: ящики и валун тянуло в дно ковша и друг в друга. Теперь каждый держится там, куда положен. Строка отладки (настройки, «Строка отладки») показывает стадию, что соединяет шарнир, угол рычага и сколько груза в ковше.

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

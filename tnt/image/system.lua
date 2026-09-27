--- Внешняя зависимость пакета: монотонные часы срока.
---
--- `transform` запускает программу дважды — осмотр заголовка и само
--- преобразование — под одним сроком, и остаток второму запуску считается
--- по часам. Подменяют их проверки: срок, кончившийся ровно между двумя
--- запусками, настоящими часами не поймать.

local clock = require('tnt.clock')
local external = require('tnt.external')

---@class TntImageSystem
---@field _set_source fun(replacement: table|nil) Подмена средств — для проверок; ставит её `external.install`
local Module = {}

---@class TntImageSource Средства пакета
---@field now fun(): number Монотонные часы, секунды

--- Действующие средства.
---@type fun(): TntImageSource
Module.current = external.install(Module, {
    now = clock.monotonic,
})

return Module

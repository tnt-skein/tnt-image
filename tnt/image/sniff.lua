--- Формат изображения по сигнатуре — первым байтам данных.
---
--- Программе формат входа называется явно (`jpeg:-`), а не отдаётся
--- на её угадывание. ImageMagick по содержимому узнаёт не только
--- картинки, но и сценарии — SVG с внешними ссылками, MVG, MSL, текст
--- `@файл`, — и данные посетителя, выданные за картинку, открыли бы ему
--- файлы узла. Сигнатура пропускает только пять растровых форматов, всё
--- прочее — отказ ещё до запуска программы, а названный формат программа
--- читает своим разборщиком и ничем другим.
---
--- Сигнатура говорит о первых байтах, а не о целом файле: мусор после
--- верного начала узнаёт программа, и это уже отказ «повреждено».

local Module = {}

--- JPEG.
Module.JPEG = 'jpeg'

--- PNG.
Module.PNG = 'png'

--- GIF.
Module.GIF = 'gif'

--- WebP.
Module.WEBP = 'webp'

--- AVIF.
Module.AVIF = 'avif'

--- Форматы по порядку — для отказов и проверки настроек.
Module.FORMATS = { Module.JPEG, Module.PNG, Module.GIF, Module.WEBP, Module.AVIF }

--- Форматы со сжатием с потерями: качество есть только у них.
Module.LOSSY = { [Module.JPEG] = true, [Module.WEBP] = true, [Module.AVIF] = true }

--- Образцы сигнатур, привязанные к началу данных.
---
--- Байты записаны через `\x`: так в образце нет чисел, которые можно
--- было бы испортить незаметно. У AVIF перед словом `ftyp` четыре байта
--- длины коробки, а за ним основная марка файла — `avif` у картинки,
--- `avis` у последовательности.
local SIGNATURES = {
    { format = Module.JPEG, pattern = '^\xFF\xD8\xFF' },
    { format = Module.PNG, pattern = '^\x89PNG\r\n\x1A\n' },
    { format = Module.GIF, pattern = '^GIF8[79]a' },
    { format = Module.WEBP, pattern = '^RIFF....WEBP' },
    { format = Module.AVIF, pattern = '^....ftypavi[fs]' },
}

--- Формат по сигнатуре; `nil` — сигнатура не узнана.
---
---     sniff.format('\xFF\xD8\xFF\xE0…')   --> 'jpeg'
---     sniff.format('<svg …')              --> nil
---@param data string
---@return string|nil
function Module.format(data)
    for _, signature in ipairs(SIGNATURES) do
        if data:find(signature.pattern) ~= nil then
            return signature.format
        end
    end

    return nil
end

return Module

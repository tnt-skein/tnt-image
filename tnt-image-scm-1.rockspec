rockspec_format = '3.0'

package = 'tnt-image'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-image.git',
    branch = 'main',
}

description = {
    summary = 'Изображения программой ImageMagick: размер, обрезка, формат, превью, отказ парой',
    detailed = [[
        Уменьшает, обрезает по области и по центру, переводит в другой
        формат с качеством, поворачивает по метке ориентации, удаляет
        метаданные и делает превью программой ImageMagick (magick либо
        convert), запущенной tnt-process: разборщик картинок живёт
        в отдельном процессе, и его падение на злом файле — отказ,
        а не упавший узел; у процесса есть срок и предел памяти.

        Формат входа узнаётся по сигнатуре (JPEG, PNG, GIF, WebP, AVIF)
        и называется программе явно — сценарии под видом картинки она
        не читает. Размер входа проверяется до запуска, сторона и число
        точек — по заголовку, до разбора точек. Отказ — пара nil, err
        с родом: не изображение, повреждено, больше предела, формат
        не по силам, область вне изображения.

        Зависит от tnt-process (запуск и отказ), tnt-fs (временный
        каталог запуска), tnt-clock (срок вызова), tnt-must (проверки
        аргументов) и tnt-external (подмена часов в проверках). Покрытие
        строк и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-image',
    issues_url = 'https://github.com/tnt-skein/tnt-image/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'image', 'imagemagick', 'thumbnail', 'webp' },
}

dependencies = {
    'lua >= 5.1',
    -- Запуск ImageMagick и отказ процесса.
    'tnt-process',
    -- Временный каталог каждого запуска.
    'tnt-fs',
    -- Монотонные часы срока вызова.
    'tnt-clock',
    -- Проверки аргументов на строке вызывающего.
    'tnt-must',
    -- Часы срока подменяются в проверках.
    'tnt-external',
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.image'] = 'tnt/image.lua',
        ['tnt.image.client'] = 'tnt/image/client.lua',
        ['tnt.image.command'] = 'tnt/image/command.lua',
        ['tnt.image.options'] = 'tnt/image/options.lua',
        ['tnt.image.sniff'] = 'tnt/image/sniff.lua',
        ['tnt.image.system'] = 'tnt/image/system.lua',
        ['tnt.image.verdict'] = 'tnt/image/verdict.lua',
    },
}

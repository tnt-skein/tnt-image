--- Приговор ImageMagick: род отказа по словам программы, причина, размеры.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local verdict = helper.verdict
local STDERR = helper.STDERR

local g = t.group('tnt.image.verdict')

--- Отказ по коду и потоку ошибок.
---@param code integer
---@param stderr string
---@return TntImageFailure|nil
local function judged(code, stderr)
    return verdict.refusal('magick', { code = code, stdout = '', stderr = stderr })
end

--- Род отказа по коду и потоку ошибок; `nil` — удача.
---@param code integer
---@param stderr string
---@return string|nil
local function kind_of(code, stderr)
    local refusal = judged(code, stderr)

    return refusal and refusal.kind
end

g.test_clean_success_is_no_refusal = function()
    t.assert_equals(judged(0, ''), nil)
    t.assert_equals(judged(0, 'tnt-image 100 50\n'), nil)
    t.assert_equals(judged(0, STDERR.srgb), nil)
    t.assert_equals(judged(0, STDERR.encoder), nil)
    t.assert_equals(judged(0, STDERR.extraneous), nil)
end

g.test_warnings_of_damage_refuse_a_success = function()
    local refusal = judged(0, STDERR.premature .. 'tnt-image 400 200\n') --[[@as TntImageFailure]]

    t.assert_equals(refusal.kind, 'corrupt')
    t.assert_equals(refusal.program, 'magick')
    t.assert_equals(refusal.code, 0)
    t.assert_equals(refusal.reason, 'Premature end of JPEG file')
    t.assert_equals(refusal.stderr, STDERR.premature .. 'tnt-image 400 200\n')
    t.assert_equals(
        tostring(refusal),
        'magick: изображение повреждено (Premature end of JPEG file)'
    )

    t.assert_equals(kind_of(0, STDERR.extraneous .. STDERR.premature), 'corrupt')
    t.assert_equals(kind_of(0, STDERR.premature .. STDERR.extraneous), 'corrupt')

    for _, words in ipairs({
        'Corrupt image',
        'premature end of data segment',
        'Truncated File Read',
        'insufficient image data in file',
        'Expected 1469 bytes; found 178 bytes',
    }) do
        t.assert_equals(kind_of(0, 'magick: ' .. words .. " `-' @ warning/x.c/F/1.\n"), 'corrupt', words)
    end

    t.assert_equals(kind_of(0, "magick: Expected some bytes `-' @ warning/png.c/F/1.\n"), nil)
    t.assert_equals(kind_of(0, "magick: Expected  bytes `-' @ warning/png.c/F/1.\n"), nil)
end

g.test_the_whole_line_about_extraneous_bytes_goes_away = function()
    t.assert_equals(kind_of(0, 'magick: Corrupt JPEG data: 2 extraneous bytes'), nil)
    t.assert_equals(kind_of(0, 'extraneous bytes before marker 0xd9, corrupt JPEG data\n'), nil)
    t.assert_equals(kind_of(0, 'magick: Corrupt JPEG data: 2 extraneous bytes\nmagick: Corrupt image\n'), 'corrupt')
end

g.test_failure_kinds_by_the_reason = function()
    t.assert_equals(kind_of(1, STDERR.exhausted), 'too_large')
    t.assert_equals(kind_of(1, STDERR.ihdr), 'too_large')
    t.assert_equals(
        kind_of(1, "magick: width or height exceeds limit `-' @ error/cache.c/OpenPixelCache/3714.\n"),
        'too_large'
    )
    t.assert_equals(kind_of(1, "magick: memory allocation failed `-' @ error/x.c/F/1.\n"), 'too_large')
    t.assert_equals(kind_of(1, STDERR.encoder), 'unsupported')
    t.assert_equals(kind_of(1, "magick: no decode delegate for this image format `' @ error/x.c/F/1.\n"), 'unsupported')
    t.assert_equals(
        kind_of(
            1,
            'magick: attempt to perform an operation not allowed by the security policy ' .. "`PS' @ error/x.c/F/1.\n"
        ),
        'unsupported'
    )
    t.assert_equals(kind_of(1, "magick: not authorized `PS' @ error/constitute.c/ReadImage/1.\n"), 'unsupported')
    t.assert_equals(kind_of(1, "magick: unable to create temporary file `-' @ error/x.c/F/1.\n"), 'failed')
    t.assert_equals(kind_of(1, "magick: No space left on device `-' @ error/x.c/F/1.\n"), 'failed')
    t.assert_equals(kind_of(1, "magick: Permission denied `-' @ error/x.c/F/1.\n"), 'failed')
    t.assert_equals(kind_of(1, "magick: unable to open image `x' @ error/blob.c/OpenBlob/1.\n"), 'failed')
    t.assert_equals(kind_of(1, "magick: user authorized `x' @ error/x.c/F/1.\n"), 'corrupt')
    t.assert_equals(kind_of(1, 'magick: something @ errorless\n'), 'failed')
end

g.test_limits_win_over_damage = function()
    local refusal = judged(1, STDERR.ihdr) --[[@as TntImageFailure]]

    t.assert_equals(refusal.kind, 'too_large')
    t.assert_equals(refusal.reason, 'Image width exceeds user limit in IHDR')
    t.assert_equals(
        tostring(refusal),
        'magick: изображение не уместилось в пределы программы (Image width exceeds user limit in IHDR)'
    )
end

g.test_an_unknown_error_of_the_program_is_damage = function()
    local refusal = judged(1, STDERR.insufficient) --[[@as TntImageFailure]]

    t.assert_equals(refusal.kind, 'corrupt')
    t.assert_equals(refusal.code, 1)
    t.assert_equals(refusal.reason, 'insufficient image data in file')
    t.assert_equals(kind_of(1, STDERR.header), 'corrupt')
    t.assert_equals(kind_of(2, STDERR.header), 'corrupt')
end

g.test_a_failure_without_a_word_of_the_program_is_no_damage = function()
    local refusal = judged(1, 'Error response from daemon: container is not running\n') --[[@as TntImageFailure]]

    t.assert_equals(refusal.kind, 'failed')
    t.assert_equals(refusal.reason, nil)
    t.assert_equals(
        tostring(refusal),
        'magick: программа не справилась (без пояснения)'
    )
    t.assert_equals(kind_of(1, ''), 'failed')
    t.assert_equals(
        kind_of(1, "magick: geometry does not contain image `-' @ warning/transform.c/CropImage/599.\n"),
        'failed'
    )
end

g.test_reason_is_the_first_message_of_the_program = function()
    t.assert_equals(verdict.reason(STDERR.premature), 'Premature end of JPEG file')
    t.assert_equals(verdict.reason('WARNING: something\n' .. STDERR.header), 'improper image header')
    t.assert_equals(verdict.reason(STDERR.encoder), 'no encode delegate for this image format')
    t.assert_equals(
        verdict.reason(
            "magick: unable to open image 'avif:-': No such file or directory @ error/blob.c/OpenBlob/3701.\n"
        ),
        'unable to open image'
    )
    t.assert_equals(verdict.reason('magick: no images defined @ error/convert.c/F/1.\n'), 'no images defined')
    t.assert_equals(verdict.reason('no program here @ error/x.c/F/1.\n'), nil)
    t.assert_equals(verdict.reason(': Read Exception @ error/png.c/F/1.\n'), 'Read Exception')
    t.assert_equals(verdict.reason('magick: something @ /x.c\n'), nil)
    t.assert_equals(verdict.reason('magick: a @ x/ b @ error/y.c/F/1.\n'), 'a')
    t.assert_equals(verdict.reason('magick: odd ` @ error/x.c/F/1.\n'), 'odd')
    t.assert_equals(verdict.reason('magick: no place\n'), nil)
    t.assert_equals(verdict.reason(''), nil)
end

g.test_size_of_the_result = function()
    t.assert_equals({ verdict.size('tnt-image 100 50\n') }, { 100, 50 })
    t.assert_equals({ verdict.size(STDERR.srgb .. 'tnt-image 7 12345\n') }, { 7, 12345 })
    t.assert_equals({ verdict.size('tnt-imageX100 50\n') }, { nil, nil })
    t.assert_equals({ verdict.size('tnt-image  50\n') }, { nil, nil })
    t.assert_equals({ verdict.size('tnt-image 100 \n') }, { nil, nil })
    t.assert_equals({ verdict.size('') }, { nil, nil })
end

g.test_new_failure_reads_as_its_text = function()
    local failure = verdict.new('invalid', 'convert', 'не изображение', { reason = 'x' })

    t.assert_equals(failure.kind, 'invalid')
    t.assert_equals(failure.program, 'convert')
    t.assert_equals(failure.reason, 'x')
    t.assert_equals(tostring(failure), 'не изображение')
    t.assert_equals('причина: ' .. failure, 'причина: не изображение')
end

g.test_words_of_the_module = function()
    t.assert_equals(
        { verdict.INVALID, verdict.CORRUPT, verdict.UNSUPPORTED, verdict.TOO_LARGE, verdict.OUTSIDE, verdict.FAILED },
        { 'invalid', 'corrupt', 'unsupported', 'too_large', 'outside', 'failed' }
    )
end

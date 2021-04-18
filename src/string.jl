# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to string processing.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _crop_str(str::AbstractString, cols_beg::Int, cols_end::Int = -1)

Crop the string `str` between the columns `cols_beg` and `cols_end`. If any of
the values are negative, then it will be selected as the string limits.

"""
function _crop_str(str::AbstractString, cols_beg::Int, cols_end::Int = -1)
    str_width = textwidth(str)

    cols_beg < 1 && (cols_beg = 1)

    cropped_str = ""
    num_cols = 1
    init = false

    for c in str
        cw = textwidth(c)

        if !init
            Δ = num_cols - cols_beg

            if Δ < 0
                if Δ + cw > 0
                    cropped_str *= " "^(Δ + cw)
                    num_cols += Δ + cw
                    init = true
                    continue
                end

                num_cols += cw
                continue
            end
        end

        num_cols += cw
        (cols_end > 0) && (num_cols > cols_end + 1) && break
        cropped_str *= c
    end

    return cropped_str
end


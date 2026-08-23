//Provides: integers_unsigned_init
// The integers package initializes native custom blocks here. Oystermark does
// not use its unsigned integer values at this boundary, and JavaScript values
// need no corresponding native registration.
function integers_unsigned_init(_unit) {
  return 0;
}

//Provides: integers_uint32_of_string
function integers_uint32_of_string(_value) { return 0; }
//Provides: integers_uint64_of_string
function integers_uint64_of_string(_value) { return 0; }
//Provides: integers_uint8_of_string
function integers_uint8_of_string(_value) { return 0; }
//Provides: integers_uint16_of_string
function integers_uint16_of_string(_value) { return 0; }
//Provides: integers_uint32_max
function integers_uint32_max(_unit) { return 0; }
//Provides: integers_uint64_max
function integers_uint64_max(_unit) { return 0; }
//Provides: integers_uint_size
function integers_uint_size(_unit) { return 4; }
//Provides: integers_ushort_size
function integers_ushort_size(_unit) { return 2; }
//Provides: integers_ulong_size
function integers_ulong_size(_unit) { return 8; }
//Provides: integers_ulonglong_size
function integers_ulonglong_size(_unit) { return 8; }
//Provides: integers_size_t_size
function integers_size_t_size(_unit) { return 8; }
//Provides: integers_uintptr_t_size
function integers_uintptr_t_size(_unit) { return 8; }
//Provides: integers_ptrdiff_t_size
function integers_ptrdiff_t_size(_unit) { return 8; }
//Provides: integers_intptr_t_size
function integers_intptr_t_size(_unit) { return 8; }

// These operations are linked through Core's optional native dependencies but
// are unreachable from Oystermark's parser/index API.
//Provides: integers_uint32_add
function integers_uint32_add(_a, _b) { return 0; }
//Provides: integers_uint32_sub
function integers_uint32_sub(_a, _b) { return 0; }
//Provides: integers_uint32_mul
function integers_uint32_mul(_a, _b) { return 0; }
//Provides: integers_uint32_div
function integers_uint32_div(_a, _b) { return 0; }
//Provides: integers_uint32_rem
function integers_uint32_rem(_a, _b) { return 0; }
//Provides: integers_uint32_logand
function integers_uint32_logand(_a, _b) { return 0; }
//Provides: integers_uint32_logor
function integers_uint32_logor(_a, _b) { return 0; }
//Provides: integers_uint32_logxor
function integers_uint32_logxor(_a, _b) { return 0; }
//Provides: integers_uint32_shift_left
function integers_uint32_shift_left(_a, _b) { return 0; }
//Provides: integers_uint32_shift_right
function integers_uint32_shift_right(_a, _b) { return 0; }
//Provides: integers_uint32_of_int
function integers_uint32_of_int(_a) { return 0; }
//Provides: integers_uint32_of_int32
function integers_uint32_of_int32(_a) { return 0; }
//Provides: integers_uint32_of_int64
function integers_uint32_of_int64(_a) { return 0; }
//Provides: integers_uint32_of_uint64
function integers_uint32_of_uint64(_a) { return 0; }
//Provides: integers_int32_of_uint32
function integers_int32_of_uint32(_a) { return 0; }
//Provides: integers_uint32_to_int
function integers_uint32_to_int(_a) { return 0; }
//Provides: integers_uint32_to_int64
function integers_uint32_to_int64(_a) { return 0; }
//Provides: integers_uint64_add
function integers_uint64_add(_a, _b) { return 0; }
//Provides: integers_uint64_sub
function integers_uint64_sub(_a, _b) { return 0; }
//Provides: integers_uint64_mul
function integers_uint64_mul(_a, _b) { return 0; }
//Provides: integers_uint64_div
function integers_uint64_div(_a, _b) { return 0; }
//Provides: integers_uint64_rem
function integers_uint64_rem(_a, _b) { return 0; }
//Provides: integers_uint64_logand
function integers_uint64_logand(_a, _b) { return 0; }
//Provides: integers_uint64_logor
function integers_uint64_logor(_a, _b) { return 0; }
//Provides: integers_uint64_logxor
function integers_uint64_logxor(_a, _b) { return 0; }
//Provides: integers_uint64_shift_left
function integers_uint64_shift_left(_a, _b) { return 0; }
//Provides: integers_uint64_shift_right
function integers_uint64_shift_right(_a, _b) { return 0; }
//Provides: integers_uint64_of_int
function integers_uint64_of_int(_a) { return 0; }
//Provides: integers_uint64_of_int64
function integers_uint64_of_int64(_a) { return 0; }
//Provides: integers_uint64_of_uint32
function integers_uint64_of_uint32(_a) { return 0; }
//Provides: integers_uint64_to_int
function integers_uint64_to_int(_a) { return 0; }
//Provides: integers_uint64_to_int64
function integers_uint64_to_int64(_a, _b) { return 0; }

//Provides: integers_uint32_to_string
function integers_uint32_to_string(_value) { return "0"; }
//Provides: integers_uint32_to_hexstring
function integers_uint32_to_hexstring(_value) { return "0"; }
//Provides: integers_uint64_to_string
function integers_uint64_to_string(_value) { return "0"; }
//Provides: integers_uint64_to_hexstring
function integers_uint64_to_hexstring(_value) { return "0"; }

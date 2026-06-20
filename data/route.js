(function(scope){
'use strict';

function F(arity, fun, wrapper) {
  wrapper.a = arity;
  wrapper.f = fun;
  return wrapper;
}

function F2(fun) {
  return F(2, fun, function(a) { return function(b) { return fun(a,b); }; })
}
function F3(fun) {
  return F(3, fun, function(a) {
    return function(b) { return function(c) { return fun(a, b, c); }; };
  });
}
function F4(fun) {
  return F(4, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return fun(a, b, c, d); }; }; };
  });
}
function F5(fun) {
  return F(5, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return fun(a, b, c, d, e); }; }; }; };
  });
}
function F6(fun) {
  return F(6, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return fun(a, b, c, d, e, f); }; }; }; }; };
  });
}
function F7(fun) {
  return F(7, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return fun(a, b, c, d, e, f, g); }; }; }; }; }; };
  });
}
function F8(fun) {
  return F(8, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) {
    return fun(a, b, c, d, e, f, g, h); }; }; }; }; }; }; };
  });
}
function F9(fun) {
  return F(9, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) { return function(i) {
    return fun(a, b, c, d, e, f, g, h, i); }; }; }; }; }; }; }; };
  });
}

function A2(fun, a, b) {
  return fun.a === 2 ? fun.f(a, b) : fun(a)(b);
}
function A3(fun, a, b, c) {
  return fun.a === 3 ? fun.f(a, b, c) : fun(a)(b)(c);
}
function A4(fun, a, b, c, d) {
  return fun.a === 4 ? fun.f(a, b, c, d) : fun(a)(b)(c)(d);
}
function A5(fun, a, b, c, d, e) {
  return fun.a === 5 ? fun.f(a, b, c, d, e) : fun(a)(b)(c)(d)(e);
}
function A6(fun, a, b, c, d, e, f) {
  return fun.a === 6 ? fun.f(a, b, c, d, e, f) : fun(a)(b)(c)(d)(e)(f);
}
function A7(fun, a, b, c, d, e, f, g) {
  return fun.a === 7 ? fun.f(a, b, c, d, e, f, g) : fun(a)(b)(c)(d)(e)(f)(g);
}
function A8(fun, a, b, c, d, e, f, g, h) {
  return fun.a === 8 ? fun.f(a, b, c, d, e, f, g, h) : fun(a)(b)(c)(d)(e)(f)(g)(h);
}
function A9(fun, a, b, c, d, e, f, g, h, i) {
  return fun.a === 9 ? fun.f(a, b, c, d, e, f, g, h, i) : fun(a)(b)(c)(d)(e)(f)(g)(h)(i);
}




// EQUALITY

function _Utils_eq(x, y)
{
	for (
		var pair, stack = [], isEqual = _Utils_eqHelp(x, y, 0, stack);
		isEqual && (pair = stack.pop());
		isEqual = _Utils_eqHelp(pair.a, pair.b, 0, stack)
		)
	{}

	return isEqual;
}

function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	/**_UNUSED/
	if (x.$ === 'Set_elm_builtin')
	{
		x = $elm$core$Set$toList(x);
		y = $elm$core$Set$toList(y);
	}
	if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	/**/
	if (x.$ < 0)
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	for (var key in x)
	{
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

function _Utils_cmp(x, y, ord)
{
	if (typeof x !== 'object')
	{
		return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
	}

	/**_UNUSED/
	if (x instanceof String)
	{
		var a = x.valueOf();
		var b = y.valueOf();
		return a === b ? 0 : a < b ? -1 : 1;
	}
	//*/

	/**/
	if (typeof x.$ === 'undefined')
	//*/
	/**_UNUSED/
	if (x.$[0] === '#')
	//*/
	{
		return (ord = _Utils_cmp(x.a, y.a))
			? ord
			: (ord = _Utils_cmp(x.b, y.b))
				? ord
				: _Utils_cmp(x.c, y.c);
	}

	// traverse conses until end of a list or a mismatch
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? $elm$core$Basics$LT : n ? $elm$core$Basics$GT : $elm$core$Basics$EQ;
});


// COMMON VALUES

var _Utils_Tuple0 = 0;
var _Utils_Tuple0_UNUSED = { $: '#0' };

function _Utils_Tuple2(a, b) { return { a: a, b: b }; }
function _Utils_Tuple2_UNUSED(a, b) { return { $: '#2', a: a, b: b }; }

function _Utils_Tuple3(a, b, c) { return { a: a, b: b, c: c }; }
function _Utils_Tuple3_UNUSED(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }

function _Utils_chr(c) { return c; }
function _Utils_chr_UNUSED(c) { return new String(c); }


// RECORDS

function _Utils_update(oldRecord, updatedFields)
{
	var newRecord = {};

	for (var key in oldRecord)
	{
		newRecord[key] = oldRecord[key];
	}

	for (var key in updatedFields)
	{
		newRecord[key] = updatedFields[key];
	}

	return newRecord;
}


// APPEND

var _Utils_append = F2(_Utils_ap);

function _Utils_ap(xs, ys)
{
	// append Strings
	if (typeof xs === 'string')
	{
		return xs + ys;
	}

	// append Lists
	if (!xs.b)
	{
		return ys;
	}
	var root = _List_Cons(xs.a, ys);
	xs = xs.b
	for (var curr = root; xs.b; xs = xs.b) // WHILE_CONS
	{
		curr = curr.b = _List_Cons(xs.a, ys);
	}
	return root;
}



var _List_Nil = { $: 0 };
var _List_Nil_UNUSED = { $: '[]' };

function _List_Cons(hd, tl) { return { $: 1, a: hd, b: tl }; }
function _List_Cons_UNUSED(hd, tl) { return { $: '::', a: hd, b: tl }; }


var _List_cons = F2(_List_Cons);

function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

function _List_toArray(xs)
{
	for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
	{
		out.push(xs.a);
	}
	return out;
}

var _List_map2 = F3(function(f, xs, ys)
{
	for (var arr = []; xs.b && ys.b; xs = xs.b, ys = ys.b) // WHILE_CONSES
	{
		arr.push(A2(f, xs.a, ys.a));
	}
	return _List_fromArray(arr);
});

var _List_map3 = F4(function(f, xs, ys, zs)
{
	for (var arr = []; xs.b && ys.b && zs.b; xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A3(f, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map4 = F5(function(f, ws, xs, ys, zs)
{
	for (var arr = []; ws.b && xs.b && ys.b && zs.b; ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A4(f, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map5 = F6(function(f, vs, ws, xs, ys, zs)
{
	for (var arr = []; vs.b && ws.b && xs.b && ys.b && zs.b; vs = vs.b, ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A5(f, vs.a, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_sortBy = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		return _Utils_cmp(f(a), f(b));
	}));
});

var _List_sortWith = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		var ord = A2(f, a, b);
		return ord === $elm$core$Basics$EQ ? 0 : ord === $elm$core$Basics$LT ? -1 : 1;
	}));
});



var _JsArray_empty = [];

function _JsArray_singleton(value)
{
    return [value];
}

function _JsArray_length(array)
{
    return array.length;
}

var _JsArray_initialize = F3(function(size, offset, func)
{
    var result = new Array(size);

    for (var i = 0; i < size; i++)
    {
        result[i] = func(offset + i);
    }

    return result;
});

var _JsArray_initializeFromList = F2(function (max, ls)
{
    var result = new Array(max);

    for (var i = 0; i < max && ls.b; i++)
    {
        result[i] = ls.a;
        ls = ls.b;
    }

    result.length = i;
    return _Utils_Tuple2(result, ls);
});

var _JsArray_unsafeGet = F2(function(index, array)
{
    return array[index];
});

var _JsArray_unsafeSet = F3(function(index, value, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[index] = value;
    return result;
});

var _JsArray_push = F2(function(value, array)
{
    var length = array.length;
    var result = new Array(length + 1);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[length] = value;
    return result;
});

var _JsArray_foldl = F3(function(func, acc, array)
{
    var length = array.length;

    for (var i = 0; i < length; i++)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_foldr = F3(function(func, acc, array)
{
    for (var i = array.length - 1; i >= 0; i--)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_map = F2(function(func, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = func(array[i]);
    }

    return result;
});

var _JsArray_indexedMap = F3(function(func, offset, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = A2(func, offset + i, array[i]);
    }

    return result;
});

var _JsArray_slice = F3(function(from, to, array)
{
    return array.slice(from, to);
});

var _JsArray_appendN = F3(function(n, dest, source)
{
    var destLen = dest.length;
    var itemsToCopy = n - destLen;

    if (itemsToCopy > source.length)
    {
        itemsToCopy = source.length;
    }

    var size = destLen + itemsToCopy;
    var result = new Array(size);

    for (var i = 0; i < destLen; i++)
    {
        result[i] = dest[i];
    }

    for (var i = 0; i < itemsToCopy; i++)
    {
        result[i + destLen] = source[i];
    }

    return result;
});



// LOG

var _Debug_log = F2(function(tag, value)
{
	return value;
});

var _Debug_log_UNUSED = F2(function(tag, value)
{
	console.log(tag + ': ' + _Debug_toString(value));
	return value;
});


// TODOS

function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}


// TO STRING

function _Debug_toString(value)
{
	return '<internals>';
}

function _Debug_toString_UNUSED(value)
{
	return _Debug_toAnsiString(false, value);
}

function _Debug_toAnsiString(ansi, value)
{
	if (typeof value === 'function')
	{
		return _Debug_internalColor(ansi, '<function>');
	}

	if (typeof value === 'boolean')
	{
		return _Debug_ctorColor(ansi, value ? 'True' : 'False');
	}

	if (typeof value === 'number')
	{
		return _Debug_numberColor(ansi, value + '');
	}

	if (value instanceof String)
	{
		return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
	}

	if (typeof value === 'string')
	{
		return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
	}

	if (typeof value === 'object' && '$' in value)
	{
		var tag = value.$;

		if (typeof tag === 'number')
		{
			return _Debug_internalColor(ansi, '<internals>');
		}

		if (tag[0] === '#')
		{
			var output = [];
			for (var k in value)
			{
				if (k === '$') continue;
				output.push(_Debug_toAnsiString(ansi, value[k]));
			}
			return '(' + output.join(',') + ')';
		}

		if (tag === 'Set_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Set')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Set$toList(value));
		}

		if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Dict')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Dict$toList(value));
		}

		if (tag === 'Array_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Array')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Array$toList(value));
		}

		if (tag === '::' || tag === '[]')
		{
			var output = '[';

			value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

			for (; value.b; value = value.b) // WHILE_CONS
			{
				output += ',' + _Debug_toAnsiString(ansi, value.a);
			}
			return output + ']';
		}

		var output = '';
		for (var i in value)
		{
			if (i === '$') continue;
			var str = _Debug_toAnsiString(ansi, value[i]);
			var c0 = str[0];
			var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
			output += ' ' + (parenless ? str : '(' + str + ')');
		}
		return _Debug_ctorColor(ansi, tag) + output;
	}

	if (typeof DataView === 'function' && value instanceof DataView)
	{
		return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
	}

	if (typeof File !== 'undefined' && value instanceof File)
	{
		return _Debug_internalColor(ansi, '<' + value.name + '>');
	}

	if (typeof value === 'object')
	{
		var output = [];
		for (var key in value)
		{
			var field = key[0] === '_' ? key.slice(1) : key;
			output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
		}
		if (output.length === 0)
		{
			return '{}';
		}
		return '{ ' + output.join(', ') + ' }';
	}

	return _Debug_internalColor(ansi, '<internals>');
}

function _Debug_addSlashes(str, isChar)
{
	var s = str
		.replace(/\\/g, '\\\\')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t')
		.replace(/\r/g, '\\r')
		.replace(/\v/g, '\\v')
		.replace(/\0/g, '\\0');

	if (isChar)
	{
		return s.replace(/\'/g, '\\\'');
	}
	else
	{
		return s.replace(/\"/g, '\\"');
	}
}

function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}


// CRASH


function _Debug_crash(identifier)
{
	throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
}


function _Debug_crash_UNUSED(identifier, fact1, fact2, fact3, fact4)
{
	switch(identifier)
	{
		case 0:
			throw new Error('What node should I take over? In JavaScript I need something like:\n\n    Elm.Main.init({\n        node: document.getElementById("elm-node")\n    })\n\nYou need to do this with any Browser.sandbox or Browser.element program.');

		case 1:
			throw new Error('Browser.application programs cannot handle URLs like this:\n\n    ' + document.location.href + '\n\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.');

		case 2:
			var jsonErrorString = fact1;
			throw new Error('Problem with the flags given to your Elm program on initialization.\n\n' + jsonErrorString);

		case 3:
			var portName = fact1;
			throw new Error('There can only be one port named `' + portName + '`, but your program has multiple.');

		case 4:
			var portName = fact1;
			var problem = fact2;
			throw new Error('Trying to send an unexpected type of value through port `' + portName + '`:\n' + problem);

		case 5:
			throw new Error('Trying to use `(==)` on functions.\nThere is no way to know if functions are "the same" in the Elm sense.\nRead more about this at https://package.elm-lang.org/packages/elm/core/latest/Basics#== which describes why it is this way and what the better version will look like.');

		case 6:
			var moduleName = fact1;
			throw new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');

		case 8:
			var moduleName = fact1;
			var region = fact2;
			var message = fact3;
			throw new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\n\n' + message);

		case 9:
			var moduleName = fact1;
			var region = fact2;
			var value = fact3;
			var message = fact4;
			throw new Error(
				'TODO in module `' + moduleName + '` from the `case` expression '
				+ _Debug_regionToString(region) + '\n\nIt received the following value:\n\n    '
				+ _Debug_toString(value).replace('\n', '\n    ')
				+ '\n\nBut the branch that handles it says:\n\n    ' + message.replace('\n', '\n    ')
			);

		case 10:
			throw new Error('Bug in https://github.com/elm/virtual-dom/issues');

		case 11:
			throw new Error('Cannot perform mod 0. Division by zero error.');
	}
}

function _Debug_regionToString(region)
{
	if (region.aV.ar === region.a7.ar)
	{
		return 'on line ' + region.aV.ar;
	}
	return 'on lines ' + region.aV.ar + ' through ' + region.a7.ar;
}



// MATH

var _Basics_add = F2(function(a, b) { return a + b; });
var _Basics_sub = F2(function(a, b) { return a - b; });
var _Basics_mul = F2(function(a, b) { return a * b; });
var _Basics_fdiv = F2(function(a, b) { return a / b; });
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
var _Basics_pow = F2(Math.pow);

var _Basics_remainderBy = F2(function(b, a) { return a % b; });

// https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/divmodnote-letter.pdf
var _Basics_modBy = F2(function(modulus, x)
{
	var answer = x % modulus;
	return modulus === 0
		? _Debug_crash(11)
		:
	((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0))
		? answer + modulus
		: answer;
});


// TRIGONOMETRY

var _Basics_pi = Math.PI;
var _Basics_e = Math.E;
var _Basics_cos = Math.cos;
var _Basics_sin = Math.sin;
var _Basics_tan = Math.tan;
var _Basics_acos = Math.acos;
var _Basics_asin = Math.asin;
var _Basics_atan = Math.atan;
var _Basics_atan2 = F2(Math.atan2);


// MORE MATH

function _Basics_toFloat(x) { return x; }
function _Basics_truncate(n) { return n | 0; }
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

var _Basics_ceiling = Math.ceil;
var _Basics_floor = Math.floor;
var _Basics_round = Math.round;
var _Basics_sqrt = Math.sqrt;
var _Basics_log = Math.log;
var _Basics_isNaN = isNaN;


// BOOLEANS

function _Basics_not(bool) { return !bool; }
var _Basics_and = F2(function(a, b) { return a && b; });
var _Basics_or  = F2(function(a, b) { return a || b; });
var _Basics_xor = F2(function(a, b) { return a !== b; });



var _String_cons = F2(function(chr, str)
{
	return chr + str;
});

function _String_uncons(string)
{
	var word = string.charCodeAt(0);
	return !isNaN(word)
		? $elm$core$Maybe$Just(
			0xD800 <= word && word <= 0xDBFF
				? _Utils_Tuple2(_Utils_chr(string[0] + string[1]), string.slice(2))
				: _Utils_Tuple2(_Utils_chr(string[0]), string.slice(1))
		)
		: $elm$core$Maybe$Nothing;
}

var _String_append = F2(function(a, b)
{
	return a + b;
});

function _String_length(str)
{
	return str.length;
}

var _String_map = F2(function(func, string)
{
	var len = string.length;
	var array = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = string.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			array[i] = func(_Utils_chr(string[i] + string[i+1]));
			i += 2;
			continue;
		}
		array[i] = func(_Utils_chr(string[i]));
		i++;
	}
	return array.join('');
});

var _String_filter = F2(function(isGood, str)
{
	var arr = [];
	var len = str.length;
	var i = 0;
	while (i < len)
	{
		var char = str[i];
		var word = str.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += str[i];
			i++;
		}

		if (isGood(_Utils_chr(char)))
		{
			arr.push(char);
		}
	}
	return arr.join('');
});

function _String_reverse(str)
{
	var len = str.length;
	var arr = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = str.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			arr[len - i] = str[i + 1];
			i++;
			arr[len - i] = str[i - 1];
			i++;
		}
		else
		{
			arr[len - i] = str[i];
			i++;
		}
	}
	return arr.join('');
}

var _String_foldl = F3(function(func, state, string)
{
	var len = string.length;
	var i = 0;
	while (i < len)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += string[i];
			i++;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_foldr = F3(function(func, state, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_split = F2(function(sep, str)
{
	return str.split(sep);
});

var _String_join = F2(function(sep, strs)
{
	return strs.join(sep);
});

var _String_slice = F3(function(start, end, str) {
	return str.slice(start, end);
});

function _String_trim(str)
{
	return str.trim();
}

function _String_trimLeft(str)
{
	return str.replace(/^\s+/, '');
}

function _String_trimRight(str)
{
	return str.replace(/\s+$/, '');
}

function _String_words(str)
{
	return _List_fromArray(str.trim().split(/\s+/g));
}

function _String_lines(str)
{
	return _List_fromArray(str.split(/\r\n|\r|\n/g));
}

function _String_toUpper(str)
{
	return str.toUpperCase();
}

function _String_toLower(str)
{
	return str.toLowerCase();
}

var _String_any = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (isGood(_Utils_chr(char)))
		{
			return true;
		}
	}
	return false;
});

var _String_all = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (!isGood(_Utils_chr(char)))
		{
			return false;
		}
	}
	return true;
});

var _String_contains = F2(function(sub, str)
{
	return str.indexOf(sub) > -1;
});

var _String_startsWith = F2(function(sub, str)
{
	return str.indexOf(sub) === 0;
});

var _String_endsWith = F2(function(sub, str)
{
	return str.length >= sub.length &&
		str.lastIndexOf(sub) === str.length - sub.length;
});

var _String_indexes = F2(function(sub, str)
{
	var subLen = sub.length;

	if (subLen < 1)
	{
		return _List_Nil;
	}

	var i = 0;
	var is = [];

	while ((i = str.indexOf(sub, i)) > -1)
	{
		is.push(i);
		i = i + subLen;
	}

	return _List_fromArray(is);
});


// TO STRING

function _String_fromNumber(number)
{
	return number + '';
}


// INT CONVERSIONS

function _String_toInt(str)
{
	var total = 0;
	var code0 = str.charCodeAt(0);
	var start = code0 == 0x2B /* + */ || code0 == 0x2D /* - */ ? 1 : 0;

	for (var i = start; i < str.length; ++i)
	{
		var code = str.charCodeAt(i);
		if (code < 0x30 || 0x39 < code)
		{
			return $elm$core$Maybe$Nothing;
		}
		total = 10 * total + code - 0x30;
	}

	return i == start
		? $elm$core$Maybe$Nothing
		: $elm$core$Maybe$Just(code0 == 0x2D ? -total : total);
}


// FLOAT CONVERSIONS

function _String_toFloat(s)
{
	// check if it is a hex, octal, or binary number
	if (s.length === 0 || /[\sxbo]/.test(s))
	{
		return $elm$core$Maybe$Nothing;
	}
	var n = +s;
	// faster isNaN check
	return n === n ? $elm$core$Maybe$Just(n) : $elm$core$Maybe$Nothing;
}

function _String_fromList(chars)
{
	return _List_toArray(chars).join('');
}




function _Char_toCode(char)
{
	var code = char.charCodeAt(0);
	if (0xD800 <= code && code <= 0xDBFF)
	{
		return (code - 0xD800) * 0x400 + char.charCodeAt(1) - 0xDC00 + 0x10000
	}
	return code;
}

function _Char_fromCode(code)
{
	return _Utils_chr(
		(code < 0 || 0x10FFFF < code)
			? '\uFFFD'
			:
		(code <= 0xFFFF)
			? String.fromCharCode(code)
			:
		(code -= 0x10000,
			String.fromCharCode(Math.floor(code / 0x400) + 0xD800, code % 0x400 + 0xDC00)
		)
	);
}

function _Char_toUpper(char)
{
	return _Utils_chr(char.toUpperCase());
}

function _Char_toLower(char)
{
	return _Utils_chr(char.toLowerCase());
}

function _Char_toLocaleUpper(char)
{
	return _Utils_chr(char.toLocaleUpperCase());
}

function _Char_toLocaleLower(char)
{
	return _Utils_chr(char.toLocaleLowerCase());
}



/**_UNUSED/
function _Json_errorToString(error)
{
	return $elm$json$Json$Decode$errorToString(error);
}
//*/


// CORE DECODERS

function _Json_succeed(msg)
{
	return {
		$: 0,
		a: msg
	};
}

function _Json_fail(msg)
{
	return {
		$: 1,
		a: msg
	};
}

function _Json_decodePrim(decoder)
{
	return { $: 2, b: decoder };
}

var _Json_decodeInt = _Json_decodePrim(function(value) {
	return (typeof value !== 'number')
		? _Json_expecting('an INT', value)
		:
	(-2147483647 < value && value < 2147483647 && (value | 0) === value)
		? $elm$core$Result$Ok(value)
		:
	(isFinite(value) && !(value % 1))
		? $elm$core$Result$Ok(value)
		: _Json_expecting('an INT', value);
});

var _Json_decodeBool = _Json_decodePrim(function(value) {
	return (typeof value === 'boolean')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a BOOL', value);
});

var _Json_decodeFloat = _Json_decodePrim(function(value) {
	return (typeof value === 'number')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FLOAT', value);
});

var _Json_decodeValue = _Json_decodePrim(function(value) {
	return $elm$core$Result$Ok(_Json_wrap(value));
});

var _Json_decodeString = _Json_decodePrim(function(value) {
	return (typeof value === 'string')
		? $elm$core$Result$Ok(value)
		: (value instanceof String)
			? $elm$core$Result$Ok(value + '')
			: _Json_expecting('a STRING', value);
});

function _Json_decodeList(decoder) { return { $: 3, b: decoder }; }
function _Json_decodeArray(decoder) { return { $: 4, b: decoder }; }

function _Json_decodeNull(value) { return { $: 5, c: value }; }

var _Json_decodeField = F2(function(field, decoder)
{
	return {
		$: 6,
		d: field,
		b: decoder
	};
});

var _Json_decodeIndex = F2(function(index, decoder)
{
	return {
		$: 7,
		e: index,
		b: decoder
	};
});

function _Json_decodeKeyValuePairs(decoder)
{
	return {
		$: 8,
		b: decoder
	};
}

function _Json_mapMany(f, decoders)
{
	return {
		$: 9,
		f: f,
		g: decoders
	};
}

var _Json_andThen = F2(function(callback, decoder)
{
	return {
		$: 10,
		b: decoder,
		h: callback
	};
});

function _Json_oneOf(decoders)
{
	return {
		$: 11,
		g: decoders
	};
}


// DECODING OBJECTS

var _Json_map1 = F2(function(f, d1)
{
	return _Json_mapMany(f, [d1]);
});

var _Json_map2 = F3(function(f, d1, d2)
{
	return _Json_mapMany(f, [d1, d2]);
});

var _Json_map3 = F4(function(f, d1, d2, d3)
{
	return _Json_mapMany(f, [d1, d2, d3]);
});

var _Json_map4 = F5(function(f, d1, d2, d3, d4)
{
	return _Json_mapMany(f, [d1, d2, d3, d4]);
});

var _Json_map5 = F6(function(f, d1, d2, d3, d4, d5)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5]);
});

var _Json_map6 = F7(function(f, d1, d2, d3, d4, d5, d6)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6]);
});

var _Json_map7 = F8(function(f, d1, d2, d3, d4, d5, d6, d7)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7]);
});

var _Json_map8 = F9(function(f, d1, d2, d3, d4, d5, d6, d7, d8)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7, d8]);
});


// DECODE

var _Json_runOnString = F2(function(decoder, string)
{
	try
	{
		var value = JSON.parse(string);
		return _Json_runHelp(decoder, value);
	}
	catch (e)
	{
		return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'This is not valid JSON! ' + e.message, _Json_wrap(string)));
	}
});

var _Json_run = F2(function(decoder, value)
{
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

function _Json_runHelp(decoder, value)
{
	switch (decoder.$)
	{
		case 2:
			return decoder.b(value);

		case 5:
			return (value === null)
				? $elm$core$Result$Ok(decoder.c)
				: _Json_expecting('null', value);

		case 3:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('a LIST', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _List_fromArray);

		case 4:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _Json_toElmArray);

		case 6:
			var field = decoder.d;
			if (typeof value !== 'object' || value === null || !(field in value))
			{
				return _Json_expecting('an OBJECT with a field named `' + field + '`', value);
			}
			var result = _Json_runHelp(decoder.b, value[field]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, field, result.a));

		case 7:
			var index = decoder.e;
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			if (index >= value.length)
			{
				return _Json_expecting('a LONGER array. Need index ' + index + ' but only see ' + value.length + ' entries', value);
			}
			var result = _Json_runHelp(decoder.b, value[index]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, index, result.a));

		case 8:
			if (typeof value !== 'object' || value === null || _Json_isArray(value))
			{
				return _Json_expecting('an OBJECT', value);
			}

			var keyValuePairs = _List_Nil;
			// TODO test perf of Object.keys and switch when support is good enough
			for (var key in value)
			{
				if (value.hasOwnProperty(key))
				{
					var result = _Json_runHelp(decoder.b, value[key]);
					if (!$elm$core$Result$isOk(result))
					{
						return $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, key, result.a));
					}
					keyValuePairs = _List_Cons(_Utils_Tuple2(key, result.a), keyValuePairs);
				}
			}
			return $elm$core$Result$Ok($elm$core$List$reverse(keyValuePairs));

		case 9:
			var answer = decoder.f;
			var decoders = decoder.g;
			for (var i = 0; i < decoders.length; i++)
			{
				var result = _Json_runHelp(decoders[i], value);
				if (!$elm$core$Result$isOk(result))
				{
					return result;
				}
				answer = answer(result.a);
			}
			return $elm$core$Result$Ok(answer);

		case 10:
			var result = _Json_runHelp(decoder.b, value);
			return (!$elm$core$Result$isOk(result))
				? result
				: _Json_runHelp(decoder.h(result.a), value);

		case 11:
			var errors = _List_Nil;
			for (var temp = decoder.g; temp.b; temp = temp.b) // WHILE_CONS
			{
				var result = _Json_runHelp(temp.a, value);
				if ($elm$core$Result$isOk(result))
				{
					return result;
				}
				errors = _List_Cons(result.a, errors);
			}
			return $elm$core$Result$Err($elm$json$Json$Decode$OneOf($elm$core$List$reverse(errors)));

		case 1:
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, decoder.a, _Json_wrap(value)));

		case 0:
			return $elm$core$Result$Ok(decoder.a);
	}
}

function _Json_runArrayDecoder(decoder, value, toElmValue)
{
	var len = value.length;
	var array = new Array(len);
	for (var i = 0; i < len; i++)
	{
		var result = _Json_runHelp(decoder, value[i]);
		if (!$elm$core$Result$isOk(result))
		{
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, i, result.a));
		}
		array[i] = result.a;
	}
	return $elm$core$Result$Ok(toElmValue(array));
}

function _Json_isArray(value)
{
	return Array.isArray(value) || (typeof FileList !== 'undefined' && value instanceof FileList);
}

function _Json_toElmArray(array)
{
	return A2($elm$core$Array$initialize, array.length, function(i) { return array[i]; });
}

function _Json_expecting(type, value)
{
	return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'Expecting ' + type, _Json_wrap(value)));
}


// EQUALITY

function _Json_equality(x, y)
{
	if (x === y)
	{
		return true;
	}

	if (x.$ !== y.$)
	{
		return false;
	}

	switch (x.$)
	{
		case 0:
		case 1:
			return x.a === y.a;

		case 2:
			return x.b === y.b;

		case 5:
			return x.c === y.c;

		case 3:
		case 4:
		case 8:
			return _Json_equality(x.b, y.b);

		case 6:
			return x.d === y.d && _Json_equality(x.b, y.b);

		case 7:
			return x.e === y.e && _Json_equality(x.b, y.b);

		case 9:
			return x.f === y.f && _Json_listEquality(x.g, y.g);

		case 10:
			return x.h === y.h && _Json_equality(x.b, y.b);

		case 11:
			return _Json_listEquality(x.g, y.g);
	}
}

function _Json_listEquality(aDecoders, bDecoders)
{
	var len = aDecoders.length;
	if (len !== bDecoders.length)
	{
		return false;
	}
	for (var i = 0; i < len; i++)
	{
		if (!_Json_equality(aDecoders[i], bDecoders[i]))
		{
			return false;
		}
	}
	return true;
}


// ENCODE

var _Json_encode = F2(function(indentLevel, value)
{
	return JSON.stringify(_Json_unwrap(value), null, indentLevel) + '';
});

function _Json_wrap_UNUSED(value) { return { $: 0, a: value }; }
function _Json_unwrap_UNUSED(value) { return value.a; }

function _Json_wrap(value) { return value; }
function _Json_unwrap(value) { return value; }

function _Json_emptyArray() { return []; }
function _Json_emptyObject() { return {}; }

var _Json_addField = F3(function(key, value, object)
{
	object[key] = _Json_unwrap(value);
	return object;
});

function _Json_addEntry(func)
{
	return F2(function(entry, array)
	{
		array.push(_Json_unwrap(func(entry)));
		return array;
	});
}

var _Json_encodeNull = _Json_wrap(null);



// TASKS

function _Scheduler_succeed(value)
{
	return {
		$: 0,
		a: value
	};
}

function _Scheduler_fail(error)
{
	return {
		$: 1,
		a: error
	};
}

function _Scheduler_binding(callback)
{
	return {
		$: 2,
		b: callback,
		c: null
	};
}

var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: 3,
		b: callback,
		d: task
	};
});

var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: 4,
		b: callback,
		d: task
	};
});

function _Scheduler_receive(callback)
{
	return {
		$: 5,
		b: callback
	};
}


// PROCESSES

var _Scheduler_guid = 0;

function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		e: _Scheduler_guid++,
		f: task,
		g: null,
		h: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

function _Scheduler_rawSend(proc, msg)
{
	proc.h.push(msg);
	_Scheduler_enqueue(proc);
}

var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.f;
		if (task.$ === 2 && task.c)
		{
			task.c();
		}

		proc.f = null;

		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
}


/* STEP PROCESSES

type alias Process =
  { $ : tag
  , id : unique_id
  , root : Task
  , stack : null | { $: SUCCEED | FAIL, a: callback, b: stack }
  , mailbox : [msg]
  }

*/


var _Scheduler_working = false;
var _Scheduler_queue = [];


function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	while (proc = _Scheduler_queue.shift())
	{
		_Scheduler_step(proc);
	}
	_Scheduler_working = false;
}


function _Scheduler_step(proc)
{
	while (proc.f)
	{
		var rootTag = proc.f.$;
		if (rootTag === 0 || rootTag === 1)
		{
			while (proc.g && proc.g.$ !== rootTag)
			{
				proc.g = proc.g.i;
			}
			if (!proc.g)
			{
				return;
			}
			proc.f = proc.g.b(proc.f.a);
			proc.g = proc.g.i;
		}
		else if (rootTag === 2)
		{
			proc.f.c = proc.f.b(function(newRoot) {
				proc.f = newRoot;
				_Scheduler_enqueue(proc);
			});
			return;
		}
		else if (rootTag === 5)
		{
			if (proc.h.length === 0)
			{
				return;
			}
			proc.f = proc.f.b(proc.h.shift());
		}
		else // if (rootTag === 3 || rootTag === 4)
		{
			proc.g = {
				$: rootTag === 3 ? 0 : 1,
				b: proc.f.b,
				i: proc.g
			};
			proc.f = proc.f.d;
		}
	}
}



function _Process_sleep(time)
{
	return _Scheduler_binding(function(callback) {
		var id = setTimeout(function() {
			callback(_Scheduler_succeed(_Utils_Tuple0));
		}, time);

		return function() { clearTimeout(id); };
	});
}




// PROGRAMS


var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.b4,
		impl.ct,
		impl.cq,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	$elm$core$Result$isOk(result) || _Debug_crash(2 /**_UNUSED/, _Json_errorToString(result.a) /**/);
	var managers = {};
	var initPair = init(result.a);
	var model = initPair.a;
	var stepper = stepperBuilder(sendToApp, model);
	var ports = _Platform_setupEffects(managers, sendToApp);

	function sendToApp(msg, viewMetadata)
	{
		var pair = A2(update, msg, model);
		stepper(model = pair.a, viewMetadata);
		_Platform_enqueueEffects(managers, pair.b, subscriptions(model));
	}

	_Platform_enqueueEffects(managers, initPair.b, subscriptions(model));

	return ports ? { ports: ports } : {};
}



// TRACK PRELOADS
//
// This is used by code in elm/browser and elm/http
// to register any HTTP requests that are triggered by init.
//


var _Platform_preload;


function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


var _Platform_effectManagers = {};


function _Platform_setupEffects(managers, sendToApp)
{
	var ports;

	// setup all necessary effect managers
	for (var key in _Platform_effectManagers)
	{
		var manager = _Platform_effectManagers[key];

		if (manager.a)
		{
			ports = ports || {};
			ports[key] = manager.a(key, sendToApp);
		}

		managers[key] = _Platform_instantiateManager(manager, sendToApp);
	}

	return ports;
}


function _Platform_createManager(init, onEffects, onSelfMsg, cmdMap, subMap)
{
	return {
		b: init,
		c: onEffects,
		d: onSelfMsg,
		e: cmdMap,
		f: subMap
	};
}


function _Platform_instantiateManager(info, sendToApp)
{
	var router = {
		g: sendToApp,
		h: undefined
	};

	var onEffects = info.c;
	var onSelfMsg = info.d;
	var cmdMap = info.e;
	var subMap = info.f;

	function loop(state)
	{
		return A2(_Scheduler_andThen, loop, _Scheduler_receive(function(msg)
		{
			var value = msg.a;

			if (msg.$ === 0)
			{
				return A3(onSelfMsg, router, value, state);
			}

			return cmdMap && subMap
				? A4(onEffects, router, value.i, value.j, state)
				: A3(onEffects, router, cmdMap ? value.i : value.j, state);
		}));
	}

	return router.h = _Scheduler_rawSpawn(A2(_Scheduler_andThen, loop, info.b));
}



// ROUTING


var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.g(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.h, {
		$: 0,
		a: msg
	});
});



// BAGS


function _Platform_leaf(home)
{
	return function(value)
	{
		return {
			$: 1,
			k: home,
			l: value
		};
	};
}


function _Platform_batch(list)
{
	return {
		$: 2,
		m: list
	};
}


var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: 3,
		n: tagger,
		o: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS
//
// Effects must be queued!
//
// Say your init contains a synchronous command, like Time.now or Time.here
//
//   - This will produce a batch of effects (FX_1)
//   - The synchronous task triggers the subsequent `update` call
//   - This will produce a batch of effects (FX_2)
//
// If we just start dispatching FX_2, subscriptions from FX_2 can be processed
// before subscriptions from FX_1. No good! Earlier versions of this code had
// this problem, leading to these reports:
//
//   https://github.com/elm/core/issues/980
//   https://github.com/elm/core/pull/981
//   https://github.com/elm/compiler/issues/1776
//
// The queue is necessary to avoid ordering issues for synchronous commands.


// Why use true/false here? Why not just check the length of the queue?
// The goal is to detect "are we currently dispatching effects?" If we
// are, we need to bail and let the ongoing while loop handle things.
//
// Now say the queue has 1 element. When we dequeue the final element,
// the queue will be empty, but we are still actively dispatching effects.
// So you could get queue jumping in a really tricky category of cases.
//
var _Platform_effectsQueue = [];
var _Platform_effectsActive = false;


function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ p: managers, q: cmdBag, r: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	for (var fx; fx = _Platform_effectsQueue.shift(); )
	{
		_Platform_dispatchEffects(fx.p, fx.q, fx.r);
	}
	_Platform_effectsActive = false;
}


function _Platform_dispatchEffects(managers, cmdBag, subBag)
{
	var effectsDict = {};
	_Platform_gatherEffects(true, cmdBag, effectsDict, null);
	_Platform_gatherEffects(false, subBag, effectsDict, null);

	for (var home in managers)
	{
		_Scheduler_rawSend(managers[home], {
			$: 'fx',
			a: effectsDict[home] || { i: _List_Nil, j: _List_Nil }
		});
	}
}


function _Platform_gatherEffects(isCmd, bag, effectsDict, taggers)
{
	switch (bag.$)
	{
		case 1:
			var home = bag.k;
			var effect = _Platform_toEffect(isCmd, home, taggers, bag.l);
			effectsDict[home] = _Platform_insert(isCmd, effect, effectsDict[home]);
			return;

		case 2:
			for (var list = bag.m; list.b; list = list.b) // WHILE_CONS
			{
				_Platform_gatherEffects(isCmd, list.a, effectsDict, taggers);
			}
			return;

		case 3:
			_Platform_gatherEffects(isCmd, bag.o, effectsDict, {
				s: bag.n,
				t: taggers
			});
			return;
	}
}


function _Platform_toEffect(isCmd, home, taggers, value)
{
	function applyTaggers(x)
	{
		for (var temp = taggers; temp; temp = temp.t)
		{
			x = temp.s(x);
		}
		return x;
	}

	var map = isCmd
		? _Platform_effectManagers[home].e
		: _Platform_effectManagers[home].f;

	return A2(map, applyTaggers, value)
}


function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { i: _List_Nil, j: _List_Nil };

	isCmd
		? (effects.i = _List_Cons(newEffect, effects.i))
		: (effects.j = _List_Cons(newEffect, effects.j));

	return effects;
}



// PORTS


function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


function _Platform_outgoingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		e: _Platform_outgoingPortMap,
		u: converter,
		a: _Platform_setupOutgoingPort
	};
	return _Platform_leaf(name);
}


var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


function _Platform_setupOutgoingPort(name)
{
	var subs = [];
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Process_sleep(0);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, cmdList, state)
	{
		for ( ; cmdList.b; cmdList = cmdList.b) // WHILE_CONS
		{
			// grab a separate reference to subs in case unsubscribe is called
			var currentSubs = subs;
			var value = _Json_unwrap(converter(cmdList.a));
			for (var i = 0; i < currentSubs.length; i++)
			{
				currentSubs[i](value);
			}
		}
		return init;
	});

	// PUBLIC API

	function subscribe(callback)
	{
		subs.push(callback);
	}

	function unsubscribe(callback)
	{
		// copy subs into a new array in case unsubscribe is called within a
		// subscribed callback
		subs = subs.slice();
		var index = subs.indexOf(callback);
		if (index >= 0)
		{
			subs.splice(index, 1);
		}
	}

	return {
		subscribe: subscribe,
		unsubscribe: unsubscribe
	};
}



// INCOMING PORTS


function _Platform_incomingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		f: _Platform_incomingPortMap,
		u: converter,
		a: _Platform_setupIncomingPort
	};
	return _Platform_leaf(name);
}


var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


function _Platform_setupIncomingPort(name, sendToApp)
{
	var subs = _List_Nil;
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Scheduler_succeed(null);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, subList, state)
	{
		subs = subList;
		return init;
	});

	// PUBLIC API

	function send(incomingValue)
	{
		var result = A2(_Json_run, converter, _Json_wrap(incomingValue));

		$elm$core$Result$isOk(result) || _Debug_crash(4, name, result.a);

		var value = result.a;
		for (var temp = subs; temp.b; temp = temp.b) // WHILE_CONS
		{
			sendToApp(temp.a(value));
		}
	}

	return { send: send };
}



// EXPORT ELM MODULES
//
// Have DEBUG and PROD versions so that we can (1) give nicer errors in
// debug mode and (2) not pay for the bits needed for that in prod mode.
//


function _Platform_export(exports)
{
	scope['Elm']
		? _Platform_mergeExportsProd(scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsProd(obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6)
				: _Platform_mergeExportsProd(obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}


function _Platform_export_UNUSED(exports)
{
	scope['Elm']
		? _Platform_mergeExportsDebug('Elm', scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsDebug(moduleName, obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6, moduleName)
				: _Platform_mergeExportsDebug(moduleName + '.' + name, obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}




// HELPERS


var _VirtualDom_divertHrefToApp;

var _VirtualDom_doc = typeof document !== 'undefined' ? document : {};


function _VirtualDom_appendChild(parent, child)
{
	parent.appendChild(child);
}

var _VirtualDom_init = F4(function(virtualNode, flagDecoder, debugMetadata, args)
{
	// NOTE: this function needs _Platform_export available to work

	/**/
	var node = args['node'];
	//*/
	/**_UNUSED/
	var node = args && args['node'] ? args['node'] : _Debug_crash(0);
	//*/

	node.parentNode.replaceChild(
		_VirtualDom_render(virtualNode, function() {}),
		node
	);

	return {};
});



// TEXT


function _VirtualDom_text(string)
{
	return {
		$: 0,
		a: string
	};
}



// NODE


var _VirtualDom_nodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 1,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_node = _VirtualDom_nodeNS(undefined);



// KEYED NODE


var _VirtualDom_keyedNodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 2,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_keyedNode = _VirtualDom_keyedNodeNS(undefined);



// CUSTOM


function _VirtualDom_custom(factList, model, render, diff)
{
	return {
		$: 3,
		d: _VirtualDom_organizeFacts(factList),
		g: model,
		h: render,
		i: diff
	};
}



// MAP


var _VirtualDom_map = F2(function(tagger, node)
{
	return {
		$: 4,
		j: tagger,
		k: node,
		b: 1 + (node.b || 0)
	};
});



// LAZY


function _VirtualDom_thunk(refs, thunk)
{
	return {
		$: 5,
		l: refs,
		m: thunk,
		k: undefined
	};
}

var _VirtualDom_lazy = F2(function(func, a)
{
	return _VirtualDom_thunk([func, a], function() {
		return func(a);
	});
});

var _VirtualDom_lazy2 = F3(function(func, a, b)
{
	return _VirtualDom_thunk([func, a, b], function() {
		return A2(func, a, b);
	});
});

var _VirtualDom_lazy3 = F4(function(func, a, b, c)
{
	return _VirtualDom_thunk([func, a, b, c], function() {
		return A3(func, a, b, c);
	});
});

var _VirtualDom_lazy4 = F5(function(func, a, b, c, d)
{
	return _VirtualDom_thunk([func, a, b, c, d], function() {
		return A4(func, a, b, c, d);
	});
});

var _VirtualDom_lazy5 = F6(function(func, a, b, c, d, e)
{
	return _VirtualDom_thunk([func, a, b, c, d, e], function() {
		return A5(func, a, b, c, d, e);
	});
});

var _VirtualDom_lazy6 = F7(function(func, a, b, c, d, e, f)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f], function() {
		return A6(func, a, b, c, d, e, f);
	});
});

var _VirtualDom_lazy7 = F8(function(func, a, b, c, d, e, f, g)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g], function() {
		return A7(func, a, b, c, d, e, f, g);
	});
});

var _VirtualDom_lazy8 = F9(function(func, a, b, c, d, e, f, g, h)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g, h], function() {
		return A8(func, a, b, c, d, e, f, g, h);
	});
});



// FACTS


var _VirtualDom_on = F2(function(key, handler)
{
	return {
		$: 'a0',
		n: key,
		o: handler
	};
});
var _VirtualDom_style = F2(function(key, value)
{
	return {
		$: 'a1',
		n: key,
		o: value
	};
});
var _VirtualDom_property = F2(function(key, value)
{
	return {
		$: 'a2',
		n: key,
		o: value
	};
});
var _VirtualDom_attribute = F2(function(key, value)
{
	return {
		$: 'a3',
		n: key,
		o: value
	};
});
var _VirtualDom_attributeNS = F3(function(namespace, key, value)
{
	return {
		$: 'a4',
		n: key,
		o: { f: namespace, o: value }
	};
});



// XSS ATTACK VECTOR CHECKS
//
// For some reason, tabs can appear in href protocols and it still works.
// So '\tjava\tSCRIPT:alert("!!!")' and 'javascript:alert("!!!")' are the same
// in practice. That is why _VirtualDom_RE_js and _VirtualDom_RE_js_html look
// so freaky.
//
// Pulling the regular expressions out to the top level gives a slight speed
// boost in small benchmarks (4-10%) but hoisting values to reduce allocation
// can be unpredictable in large programs where JIT may have a harder time with
// functions are not fully self-contained. The benefit is more that the js and
// js_html ones are so weird that I prefer to see them near each other.


var _VirtualDom_RE_script = /^script$/i;
var _VirtualDom_RE_on_formAction = /^(on|formAction$)/i;
var _VirtualDom_RE_js = /^\s*j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:/i;
var _VirtualDom_RE_js_html = /^\s*(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:|d\s*a\s*t\s*a\s*:\s*t\s*e\s*x\s*t\s*\/\s*h\s*t\s*m\s*l\s*(,|;))/i;


function _VirtualDom_noScript(tag)
{
	return _VirtualDom_RE_script.test(tag) ? 'p' : tag;
}

function _VirtualDom_noOnOrFormAction(key)
{
	return _VirtualDom_RE_on_formAction.test(key) ? 'data-' + key : key;
}

function _VirtualDom_noInnerHtmlOrFormAction(key)
{
	return key == 'innerHTML' || key == 'formAction' ? 'data-' + key : key;
}

function _VirtualDom_noJavaScriptUri(value)
{
	return _VirtualDom_RE_js.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlUri(value)
{
	return _VirtualDom_RE_js_html.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlJson(value)
{
	return (typeof _Json_unwrap(value) === 'string' && _VirtualDom_RE_js_html.test(_Json_unwrap(value)))
		? _Json_wrap(
			/**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		) : value;
}



// MAP FACTS


var _VirtualDom_mapAttribute = F2(function(func, attr)
{
	return (attr.$ === 'a0')
		? A2(_VirtualDom_on, attr.n, _VirtualDom_mapHandler(func, attr.o))
		: attr;
});

function _VirtualDom_mapHandler(func, handler)
{
	var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

	// 0 = Normal
	// 1 = MayStopPropagation
	// 2 = MayPreventDefault
	// 3 = Custom

	return {
		$: handler.$,
		a:
			!tag
				? A2($elm$json$Json$Decode$map, func, handler.a)
				:
			A3($elm$json$Json$Decode$map2,
				tag < 3
					? _VirtualDom_mapEventTuple
					: _VirtualDom_mapEventRecord,
				$elm$json$Json$Decode$succeed(func),
				handler.a
			)
	};
}

var _VirtualDom_mapEventTuple = F2(function(func, tuple)
{
	return _Utils_Tuple2(func(tuple.a), tuple.b);
});

var _VirtualDom_mapEventRecord = F2(function(func, record)
{
	return {
		bl: func(record.bl),
		bG: record.bG,
		bs: record.bs
	}
});



// ORGANIZE FACTS


function _VirtualDom_organizeFacts(factList)
{
	for (var facts = {}; factList.b; factList = factList.b) // WHILE_CONS
	{
		var entry = factList.a;

		var tag = entry.$;
		var key = entry.n;
		var value = entry.o;

		if (tag === 'a2')
		{
			(key === 'className')
				? _VirtualDom_addClass(facts, key, _Json_unwrap(value))
				: facts[key] = _Json_unwrap(value);

			continue;
		}

		var subFacts = facts[tag] || (facts[tag] = {});
		(tag === 'a3' && key === 'class')
			? _VirtualDom_addClass(subFacts, key, value)
			: subFacts[key] = value;
	}

	return facts;
}

function _VirtualDom_addClass(object, key, newClass)
{
	var classes = object[key];
	object[key] = classes ? classes + ' ' + newClass : newClass;
}



// RENDER


function _VirtualDom_render(vNode, eventNode)
{
	var tag = vNode.$;

	if (tag === 5)
	{
		return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
	}

	if (tag === 0)
	{
		return _VirtualDom_doc.createTextNode(vNode.a);
	}

	if (tag === 4)
	{
		var subNode = vNode.k;
		var tagger = vNode.j;

		while (subNode.$ === 4)
		{
			typeof tagger !== 'object'
				? tagger = [tagger, subNode.j]
				: tagger.push(subNode.j);

			subNode = subNode.k;
		}

		var subEventRoot = { j: tagger, p: eventNode };
		var domNode = _VirtualDom_render(subNode, subEventRoot);
		domNode.elm_event_node_ref = subEventRoot;
		return domNode;
	}

	if (tag === 3)
	{
		var domNode = vNode.h(vNode.g);
		_VirtualDom_applyFacts(domNode, eventNode, vNode.d);
		return domNode;
	}

	// at this point `tag` must be 1 or 2

	var domNode = vNode.f
		? _VirtualDom_doc.createElementNS(vNode.f, vNode.c)
		: _VirtualDom_doc.createElement(vNode.c);

	if (_VirtualDom_divertHrefToApp && vNode.c == 'a')
	{
		domNode.addEventListener('click', _VirtualDom_divertHrefToApp(domNode));
	}

	_VirtualDom_applyFacts(domNode, eventNode, vNode.d);

	for (var kids = vNode.e, i = 0; i < kids.length; i++)
	{
		_VirtualDom_appendChild(domNode, _VirtualDom_render(tag === 1 ? kids[i] : kids[i].b, eventNode));
	}

	return domNode;
}



// APPLY FACTS


function _VirtualDom_applyFacts(domNode, eventNode, facts)
{
	for (var key in facts)
	{
		var value = facts[key];

		key === 'a1'
			? _VirtualDom_applyStyles(domNode, value)
			:
		key === 'a0'
			? _VirtualDom_applyEvents(domNode, eventNode, value)
			:
		key === 'a3'
			? _VirtualDom_applyAttrs(domNode, value)
			:
		key === 'a4'
			? _VirtualDom_applyAttrsNS(domNode, value)
			:
		((key !== 'value' && key !== 'checked') || domNode[key] !== value) && (domNode[key] = value);
	}
}



// APPLY STYLES


function _VirtualDom_applyStyles(domNode, styles)
{
	var domNodeStyle = domNode.style;

	for (var key in styles)
	{
		domNodeStyle[key] = styles[key];
	}
}



// APPLY ATTRS


function _VirtualDom_applyAttrs(domNode, attrs)
{
	for (var key in attrs)
	{
		var value = attrs[key];
		typeof value !== 'undefined'
			? domNode.setAttribute(key, value)
			: domNode.removeAttribute(key);
	}
}



// APPLY NAMESPACED ATTRS


function _VirtualDom_applyAttrsNS(domNode, nsAttrs)
{
	for (var key in nsAttrs)
	{
		var pair = nsAttrs[key];
		var namespace = pair.f;
		var value = pair.o;

		typeof value !== 'undefined'
			? domNode.setAttributeNS(namespace, key, value)
			: domNode.removeAttributeNS(namespace, key);
	}
}



// APPLY EVENTS


function _VirtualDom_applyEvents(domNode, eventNode, events)
{
	var allCallbacks = domNode.elmFs || (domNode.elmFs = {});

	for (var key in events)
	{
		var newHandler = events[key];
		var oldCallback = allCallbacks[key];

		if (!newHandler)
		{
			domNode.removeEventListener(key, oldCallback);
			allCallbacks[key] = undefined;
			continue;
		}

		if (oldCallback)
		{
			var oldHandler = oldCallback.q;
			if (oldHandler.$ === newHandler.$)
			{
				oldCallback.q = newHandler;
				continue;
			}
			domNode.removeEventListener(key, oldCallback);
		}

		oldCallback = _VirtualDom_makeCallback(eventNode, newHandler);
		domNode.addEventListener(key, oldCallback,
			_VirtualDom_passiveSupported
			&& { passive: $elm$virtual_dom$VirtualDom$toHandlerInt(newHandler) < 2 }
		);
		allCallbacks[key] = oldCallback;
	}
}



// PASSIVE EVENTS


var _VirtualDom_passiveSupported;

try
{
	window.addEventListener('t', null, Object.defineProperty({}, 'passive', {
		get: function() { _VirtualDom_passiveSupported = true; }
	}));
}
catch(e) {}



// EVENT HANDLERS


function _VirtualDom_makeCallback(eventNode, initialHandler)
{
	function callback(event)
	{
		var handler = callback.q;
		var result = _Json_runHelp(handler.a, event);

		if (!$elm$core$Result$isOk(result))
		{
			return;
		}

		var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

		// 0 = Normal
		// 1 = MayStopPropagation
		// 2 = MayPreventDefault
		// 3 = Custom

		var value = result.a;
		var message = !tag ? value : tag < 3 ? value.a : value.bl;
		var stopPropagation = tag == 1 ? value.b : tag == 3 && value.bG;
		var currentEventNode = (
			stopPropagation && event.stopPropagation(),
			(tag == 2 ? value.b : tag == 3 && value.bs) && event.preventDefault(),
			eventNode
		);
		var tagger;
		var i;
		while (tagger = currentEventNode.j)
		{
			if (typeof tagger == 'function')
			{
				message = tagger(message);
			}
			else
			{
				for (var i = tagger.length; i--; )
				{
					message = tagger[i](message);
				}
			}
			currentEventNode = currentEventNode.p;
		}
		currentEventNode(message, stopPropagation); // stopPropagation implies isSync
	}

	callback.q = initialHandler;

	return callback;
}

function _VirtualDom_equalEvents(x, y)
{
	return x.$ == y.$ && _Json_equality(x.a, y.a);
}



// DIFF


// TODO: Should we do patches like in iOS?
//
// type Patch
//   = At Int Patch
//   | Batch (List Patch)
//   | Change ...
//
// How could it not be better?
//
function _VirtualDom_diff(x, y)
{
	var patches = [];
	_VirtualDom_diffHelp(x, y, patches, 0);
	return patches;
}


function _VirtualDom_pushPatch(patches, type, index, data)
{
	var patch = {
		$: type,
		r: index,
		s: data,
		t: undefined,
		u: undefined
	};
	patches.push(patch);
	return patch;
}


function _VirtualDom_diffHelp(x, y, patches, index)
{
	if (x === y)
	{
		return;
	}

	var xType = x.$;
	var yType = y.$;

	// Bail if you run into different types of nodes. Implies that the
	// structure has changed significantly and it's not worth a diff.
	if (xType !== yType)
	{
		if (xType === 1 && yType === 2)
		{
			y = _VirtualDom_dekey(y);
			yType = 1;
		}
		else
		{
			_VirtualDom_pushPatch(patches, 0, index, y);
			return;
		}
	}

	// Now we know that both nodes are the same $.
	switch (yType)
	{
		case 5:
			var xRefs = x.l;
			var yRefs = y.l;
			var i = xRefs.length;
			var same = i === yRefs.length;
			while (same && i--)
			{
				same = xRefs[i] === yRefs[i];
			}
			if (same)
			{
				y.k = x.k;
				return;
			}
			y.k = y.m();
			var subPatches = [];
			_VirtualDom_diffHelp(x.k, y.k, subPatches, 0);
			subPatches.length > 0 && _VirtualDom_pushPatch(patches, 1, index, subPatches);
			return;

		case 4:
			// gather nested taggers
			var xTaggers = x.j;
			var yTaggers = y.j;
			var nesting = false;

			var xSubNode = x.k;
			while (xSubNode.$ === 4)
			{
				nesting = true;

				typeof xTaggers !== 'object'
					? xTaggers = [xTaggers, xSubNode.j]
					: xTaggers.push(xSubNode.j);

				xSubNode = xSubNode.k;
			}

			var ySubNode = y.k;
			while (ySubNode.$ === 4)
			{
				nesting = true;

				typeof yTaggers !== 'object'
					? yTaggers = [yTaggers, ySubNode.j]
					: yTaggers.push(ySubNode.j);

				ySubNode = ySubNode.k;
			}

			// Just bail if different numbers of taggers. This implies the
			// structure of the virtual DOM has changed.
			if (nesting && xTaggers.length !== yTaggers.length)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			// check if taggers are "the same"
			if (nesting ? !_VirtualDom_pairwiseRefEqual(xTaggers, yTaggers) : xTaggers !== yTaggers)
			{
				_VirtualDom_pushPatch(patches, 2, index, yTaggers);
			}

			// diff everything below the taggers
			_VirtualDom_diffHelp(xSubNode, ySubNode, patches, index + 1);
			return;

		case 0:
			if (x.a !== y.a)
			{
				_VirtualDom_pushPatch(patches, 3, index, y.a);
			}
			return;

		case 1:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKids);
			return;

		case 2:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKeyedKids);
			return;

		case 3:
			if (x.h !== y.h)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
			factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

			var patch = y.i(x.g, y.g);
			patch && _VirtualDom_pushPatch(patches, 5, index, patch);

			return;
	}
}

// assumes the incoming arrays are the same length
function _VirtualDom_pairwiseRefEqual(as, bs)
{
	for (var i = 0; i < as.length; i++)
	{
		if (as[i] !== bs[i])
		{
			return false;
		}
	}

	return true;
}

function _VirtualDom_diffNodes(x, y, patches, index, diffKids)
{
	// Bail if obvious indicators have changed. Implies more serious
	// structural changes such that it's not worth it to diff.
	if (x.c !== y.c || x.f !== y.f)
	{
		_VirtualDom_pushPatch(patches, 0, index, y);
		return;
	}

	var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
	factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

	diffKids(x, y, patches, index);
}



// DIFF FACTS


// TODO Instead of creating a new diff object, it's possible to just test if
// there *is* a diff. During the actual patch, do the diff again and make the
// modifications directly. This way, there's no new allocations. Worth it?
function _VirtualDom_diffFacts(x, y, category)
{
	var diff;

	// look for changes and removals
	for (var xKey in x)
	{
		if (xKey === 'a1' || xKey === 'a0' || xKey === 'a3' || xKey === 'a4')
		{
			var subDiff = _VirtualDom_diffFacts(x[xKey], y[xKey] || {}, xKey);
			if (subDiff)
			{
				diff = diff || {};
				diff[xKey] = subDiff;
			}
			continue;
		}

		// remove if not in the new facts
		if (!(xKey in y))
		{
			diff = diff || {};
			diff[xKey] =
				!category
					? (typeof x[xKey] === 'string' ? '' : null)
					:
				(category === 'a1')
					? ''
					:
				(category === 'a0' || category === 'a3')
					? undefined
					:
				{ f: x[xKey].f, o: undefined };

			continue;
		}

		var xValue = x[xKey];
		var yValue = y[xKey];

		// reference equal, so don't worry about it
		if (xValue === yValue && xKey !== 'value' && xKey !== 'checked'
			|| category === 'a0' && _VirtualDom_equalEvents(xValue, yValue))
		{
			continue;
		}

		diff = diff || {};
		diff[xKey] = yValue;
	}

	// add new stuff
	for (var yKey in y)
	{
		if (!(yKey in x))
		{
			diff = diff || {};
			diff[yKey] = y[yKey];
		}
	}

	return diff;
}



// DIFF KIDS


function _VirtualDom_diffKids(xParent, yParent, patches, index)
{
	var xKids = xParent.e;
	var yKids = yParent.e;

	var xLen = xKids.length;
	var yLen = yKids.length;

	// FIGURE OUT IF THERE ARE INSERTS OR REMOVALS

	if (xLen > yLen)
	{
		_VirtualDom_pushPatch(patches, 6, index, {
			v: yLen,
			i: xLen - yLen
		});
	}
	else if (xLen < yLen)
	{
		_VirtualDom_pushPatch(patches, 7, index, {
			v: xLen,
			e: yKids
		});
	}

	// PAIRWISE DIFF EVERYTHING ELSE

	for (var minLen = xLen < yLen ? xLen : yLen, i = 0; i < minLen; i++)
	{
		var xKid = xKids[i];
		_VirtualDom_diffHelp(xKid, yKids[i], patches, ++index);
		index += xKid.b || 0;
	}
}



// KEYED DIFF


function _VirtualDom_diffKeyedKids(xParent, yParent, patches, rootIndex)
{
	var localPatches = [];

	var changes = {}; // Dict String Entry
	var inserts = []; // Array { index : Int, entry : Entry }
	// type Entry = { tag : String, vnode : VNode, index : Int, data : _ }

	var xKids = xParent.e;
	var yKids = yParent.e;
	var xLen = xKids.length;
	var yLen = yKids.length;
	var xIndex = 0;
	var yIndex = 0;

	var index = rootIndex;

	while (xIndex < xLen && yIndex < yLen)
	{
		var x = xKids[xIndex];
		var y = yKids[yIndex];

		var xKey = x.a;
		var yKey = y.a;
		var xNode = x.b;
		var yNode = y.b;

		var newMatch = undefined;
		var oldMatch = undefined;

		// check if keys match

		if (xKey === yKey)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNode, localPatches, index);
			index += xNode.b || 0;

			xIndex++;
			yIndex++;
			continue;
		}

		// look ahead 1 to detect insertions and removals.

		var xNext = xKids[xIndex + 1];
		var yNext = yKids[yIndex + 1];

		if (xNext)
		{
			var xNextKey = xNext.a;
			var xNextNode = xNext.b;
			oldMatch = yKey === xNextKey;
		}

		if (yNext)
		{
			var yNextKey = yNext.a;
			var yNextNode = yNext.b;
			newMatch = xKey === yNextKey;
		}


		// swap x and y
		if (newMatch && oldMatch)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			_VirtualDom_insertNode(changes, localPatches, xKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNextNode, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		// insert y
		if (newMatch)
		{
			index++;
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			index += xNode.b || 0;

			xIndex += 1;
			yIndex += 2;
			continue;
		}

		// remove x
		if (oldMatch)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 1;
			continue;
		}

		// remove x, insert y
		if (xNext && xNextKey === yNextKey)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNextNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		break;
	}

	// eat up any remaining nodes with removeNode and insertNode

	while (xIndex < xLen)
	{
		index++;
		var x = xKids[xIndex];
		var xNode = x.b;
		_VirtualDom_removeNode(changes, localPatches, x.a, xNode, index);
		index += xNode.b || 0;
		xIndex++;
	}

	while (yIndex < yLen)
	{
		var endInserts = endInserts || [];
		var y = yKids[yIndex];
		_VirtualDom_insertNode(changes, localPatches, y.a, y.b, undefined, endInserts);
		yIndex++;
	}

	if (localPatches.length > 0 || inserts.length > 0 || endInserts)
	{
		_VirtualDom_pushPatch(patches, 8, rootIndex, {
			w: localPatches,
			x: inserts,
			y: endInserts
		});
	}
}



// CHANGES FROM KEYED DIFF


var _VirtualDom_POSTFIX = '_elmW6BL';


function _VirtualDom_insertNode(changes, localPatches, key, vnode, yIndex, inserts)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		entry = {
			c: 0,
			z: vnode,
			r: yIndex,
			s: undefined
		};

		inserts.push({ r: yIndex, A: entry });
		changes[key] = entry;

		return;
	}

	// this key was removed earlier, a match!
	if (entry.c === 1)
	{
		inserts.push({ r: yIndex, A: entry });

		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(entry.z, vnode, subPatches, entry.r);
		entry.r = yIndex;
		entry.s.s = {
			w: subPatches,
			A: entry
		};

		return;
	}

	// this key has already been inserted or moved, a duplicate!
	_VirtualDom_insertNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, yIndex, inserts);
}


function _VirtualDom_removeNode(changes, localPatches, key, vnode, index)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		var patch = _VirtualDom_pushPatch(localPatches, 9, index, undefined);

		changes[key] = {
			c: 1,
			z: vnode,
			r: index,
			s: patch
		};

		return;
	}

	// this key was inserted earlier, a match!
	if (entry.c === 0)
	{
		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(vnode, entry.z, subPatches, index);

		_VirtualDom_pushPatch(localPatches, 9, index, {
			w: subPatches,
			A: entry
		});

		return;
	}

	// this key has already been removed or moved, a duplicate!
	_VirtualDom_removeNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, index);
}



// ADD DOM NODES
//
// Each DOM node has an "index" assigned in order of traversal. It is important
// to minimize our crawl over the actual DOM, so these indexes (along with the
// descendantsCount of virtual nodes) let us skip touching entire subtrees of
// the DOM if we know there are no patches there.


function _VirtualDom_addDomNodes(domNode, vNode, patches, eventNode)
{
	_VirtualDom_addDomNodesHelp(domNode, vNode, patches, 0, 0, vNode.b, eventNode);
}


// assumes `patches` is non-empty and indexes increase monotonically.
function _VirtualDom_addDomNodesHelp(domNode, vNode, patches, i, low, high, eventNode)
{
	var patch = patches[i];
	var index = patch.r;

	while (index === low)
	{
		var patchType = patch.$;

		if (patchType === 1)
		{
			_VirtualDom_addDomNodes(domNode, vNode.k, patch.s, eventNode);
		}
		else if (patchType === 8)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var subPatches = patch.s.w;
			if (subPatches.length > 0)
			{
				_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
			}
		}
		else if (patchType === 9)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var data = patch.s;
			if (data)
			{
				data.A.s = domNode;
				var subPatches = data.w;
				if (subPatches.length > 0)
				{
					_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
				}
			}
		}
		else
		{
			patch.t = domNode;
			patch.u = eventNode;
		}

		i++;

		if (!(patch = patches[i]) || (index = patch.r) > high)
		{
			return i;
		}
	}

	var tag = vNode.$;

	if (tag === 4)
	{
		var subNode = vNode.k;

		while (subNode.$ === 4)
		{
			subNode = subNode.k;
		}

		return _VirtualDom_addDomNodesHelp(domNode, subNode, patches, i, low + 1, high, domNode.elm_event_node_ref);
	}

	// tag must be 1 or 2 at this point

	var vKids = vNode.e;
	var childNodes = domNode.childNodes;
	for (var j = 0; j < vKids.length; j++)
	{
		low++;
		var vKid = tag === 1 ? vKids[j] : vKids[j].b;
		var nextLow = low + (vKid.b || 0);
		if (low <= index && index <= nextLow)
		{
			i = _VirtualDom_addDomNodesHelp(childNodes[j], vKid, patches, i, low, nextLow, eventNode);
			if (!(patch = patches[i]) || (index = patch.r) > high)
			{
				return i;
			}
		}
		low = nextLow;
	}
	return i;
}



// APPLY PATCHES


function _VirtualDom_applyPatches(rootDomNode, oldVirtualNode, patches, eventNode)
{
	if (patches.length === 0)
	{
		return rootDomNode;
	}

	_VirtualDom_addDomNodes(rootDomNode, oldVirtualNode, patches, eventNode);
	return _VirtualDom_applyPatchesHelp(rootDomNode, patches);
}

function _VirtualDom_applyPatchesHelp(rootDomNode, patches)
{
	for (var i = 0; i < patches.length; i++)
	{
		var patch = patches[i];
		var localDomNode = patch.t
		var newNode = _VirtualDom_applyPatch(localDomNode, patch);
		if (localDomNode === rootDomNode)
		{
			rootDomNode = newNode;
		}
	}
	return rootDomNode;
}

function _VirtualDom_applyPatch(domNode, patch)
{
	switch (patch.$)
	{
		case 0:
			return _VirtualDom_applyPatchRedraw(domNode, patch.s, patch.u);

		case 4:
			_VirtualDom_applyFacts(domNode, patch.u, patch.s);
			return domNode;

		case 3:
			domNode.replaceData(0, domNode.length, patch.s);
			return domNode;

		case 1:
			return _VirtualDom_applyPatchesHelp(domNode, patch.s);

		case 2:
			if (domNode.elm_event_node_ref)
			{
				domNode.elm_event_node_ref.j = patch.s;
			}
			else
			{
				domNode.elm_event_node_ref = { j: patch.s, p: patch.u };
			}
			return domNode;

		case 6:
			var data = patch.s;
			for (var i = 0; i < data.i; i++)
			{
				domNode.removeChild(domNode.childNodes[data.v]);
			}
			return domNode;

		case 7:
			var data = patch.s;
			var kids = data.e;
			var i = data.v;
			var theEnd = domNode.childNodes[i];
			for (; i < kids.length; i++)
			{
				domNode.insertBefore(_VirtualDom_render(kids[i], patch.u), theEnd);
			}
			return domNode;

		case 9:
			var data = patch.s;
			if (!data)
			{
				domNode.parentNode.removeChild(domNode);
				return domNode;
			}
			var entry = data.A;
			if (typeof entry.r !== 'undefined')
			{
				domNode.parentNode.removeChild(domNode);
			}
			entry.s = _VirtualDom_applyPatchesHelp(domNode, data.w);
			return domNode;

		case 8:
			return _VirtualDom_applyPatchReorder(domNode, patch);

		case 5:
			return patch.s(domNode);

		default:
			_Debug_crash(10); // 'Ran into an unknown patch!'
	}
}


function _VirtualDom_applyPatchRedraw(domNode, vNode, eventNode)
{
	var parentNode = domNode.parentNode;
	var newNode = _VirtualDom_render(vNode, eventNode);

	if (!newNode.elm_event_node_ref)
	{
		newNode.elm_event_node_ref = domNode.elm_event_node_ref;
	}

	if (parentNode && newNode !== domNode)
	{
		parentNode.replaceChild(newNode, domNode);
	}
	return newNode;
}


function _VirtualDom_applyPatchReorder(domNode, patch)
{
	var data = patch.s;

	// remove end inserts
	var frag = _VirtualDom_applyPatchReorderEndInsertsHelp(data.y, patch);

	// removals
	domNode = _VirtualDom_applyPatchesHelp(domNode, data.w);

	// inserts
	var inserts = data.x;
	for (var i = 0; i < inserts.length; i++)
	{
		var insert = inserts[i];
		var entry = insert.A;
		var node = entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u);
		domNode.insertBefore(node, domNode.childNodes[insert.r]);
	}

	// add end inserts
	if (frag)
	{
		_VirtualDom_appendChild(domNode, frag);
	}

	return domNode;
}


function _VirtualDom_applyPatchReorderEndInsertsHelp(endInserts, patch)
{
	if (!endInserts)
	{
		return;
	}

	var frag = _VirtualDom_doc.createDocumentFragment();
	for (var i = 0; i < endInserts.length; i++)
	{
		var insert = endInserts[i];
		var entry = insert.A;
		_VirtualDom_appendChild(frag, entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u)
		);
	}
	return frag;
}


function _VirtualDom_virtualize(node)
{
	// TEXT NODES

	if (node.nodeType === 3)
	{
		return _VirtualDom_text(node.textContent);
	}


	// WEIRD NODES

	if (node.nodeType !== 1)
	{
		return _VirtualDom_text('');
	}


	// ELEMENT NODES

	var attrList = _List_Nil;
	var attrs = node.attributes;
	for (var i = attrs.length; i--; )
	{
		var attr = attrs[i];
		var name = attr.name;
		var value = attr.value;
		attrList = _List_Cons( A2(_VirtualDom_attribute, name, value), attrList );
	}

	var tag = node.tagName.toLowerCase();
	var kidList = _List_Nil;
	var kids = node.childNodes;

	for (var i = kids.length; i--; )
	{
		kidList = _List_Cons(_VirtualDom_virtualize(kids[i]), kidList);
	}
	return A3(_VirtualDom_node, tag, attrList, kidList);
}

function _VirtualDom_dekey(keyedNode)
{
	var keyedKids = keyedNode.e;
	var len = keyedKids.length;
	var kids = new Array(len);
	for (var i = 0; i < len; i++)
	{
		kids[i] = keyedKids[i].b;
	}

	return {
		$: 1,
		c: keyedNode.c,
		d: keyedNode.d,
		e: kids,
		f: keyedNode.f,
		b: keyedNode.b
	};
}




// ELEMENT


var _Debugger_element;

var _Browser_element = _Debugger_element || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.b4,
		impl.ct,
		impl.cq,
		function(sendToApp, initialModel) {
			var view = impl.cu;
			/**/
			var domNode = args['node'];
			//*/
			/**_UNUSED/
			var domNode = args && args['node'] ? args['node'] : _Debug_crash(0);
			//*/
			var currNode = _VirtualDom_virtualize(domNode);

			return _Browser_makeAnimator(initialModel, function(model)
			{
				var nextNode = view(model);
				var patches = _VirtualDom_diff(currNode, nextNode);
				domNode = _VirtualDom_applyPatches(domNode, currNode, patches, sendToApp);
				currNode = nextNode;
			});
		}
	);
});



// DOCUMENT


var _Debugger_document;

var _Browser_document = _Debugger_document || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.b4,
		impl.ct,
		impl.cq,
		function(sendToApp, initialModel) {
			var divertHrefToApp = impl.aU && impl.aU(sendToApp)
			var view = impl.cu;
			var title = _VirtualDom_doc.title;
			var bodyNode = _VirtualDom_doc.body;
			var currNode = _VirtualDom_virtualize(bodyNode);
			return _Browser_makeAnimator(initialModel, function(model)
			{
				_VirtualDom_divertHrefToApp = divertHrefToApp;
				var doc = view(model);
				var nextNode = _VirtualDom_node('body')(_List_Nil)(doc.bV);
				var patches = _VirtualDom_diff(currNode, nextNode);
				bodyNode = _VirtualDom_applyPatches(bodyNode, currNode, patches, sendToApp);
				currNode = nextNode;
				_VirtualDom_divertHrefToApp = 0;
				(title !== doc.cs) && (_VirtualDom_doc.title = title = doc.cs);
			});
		}
	);
});



// ANIMATION


var _Browser_cancelAnimationFrame =
	typeof cancelAnimationFrame !== 'undefined'
		? cancelAnimationFrame
		: function(id) { clearTimeout(id); };

var _Browser_requestAnimationFrame =
	typeof requestAnimationFrame !== 'undefined'
		? requestAnimationFrame
		: function(callback) { return setTimeout(callback, 1000 / 60); };


function _Browser_makeAnimator(model, draw)
{
	draw(model);

	var state = 0;

	function updateIfNeeded()
	{
		state = state === 1
			? 0
			: ( _Browser_requestAnimationFrame(updateIfNeeded), draw(model), 1 );
	}

	return function(nextModel, isSync)
	{
		model = nextModel;

		isSync
			? ( draw(model),
				state === 2 && (state = 1)
				)
			: ( state === 0 && _Browser_requestAnimationFrame(updateIfNeeded),
				state = 2
				);
	};
}



// APPLICATION


function _Browser_application(impl)
{
	var onUrlChange = impl.cc;
	var onUrlRequest = impl.cd;
	var key = function() { key.a(onUrlChange(_Browser_getUrl())); };

	return _Browser_document({
		aU: function(sendToApp)
		{
			key.a = sendToApp;
			_Browser_window.addEventListener('popstate', key);
			_Browser_window.navigator.userAgent.indexOf('Trident') < 0 || _Browser_window.addEventListener('hashchange', key);

			return F2(function(domNode, event)
			{
				if (!event.ctrlKey && !event.metaKey && !event.shiftKey && event.button < 1 && !domNode.target && !domNode.hasAttribute('download'))
				{
					event.preventDefault();
					var href = domNode.href;
					var curr = _Browser_getUrl();
					var next = $elm$url$Url$fromString(href).a;
					sendToApp(onUrlRequest(
						(next
							&& curr.bv === next.bv
							&& curr.bd === next.bd
							&& curr.br.a === next.br.a
						)
							? $elm$browser$Browser$Internal(next)
							: $elm$browser$Browser$External(href)
					));
				}
			});
		},
		b4: function(flags)
		{
			return A3(impl.b4, flags, _Browser_getUrl(), key);
		},
		cu: impl.cu,
		ct: impl.ct,
		cq: impl.cq
	});
}

function _Browser_getUrl()
{
	return $elm$url$Url$fromString(_VirtualDom_doc.location.href).a || _Debug_crash(1);
}

var _Browser_go = F2(function(key, n)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		n && history.go(n);
		key();
	}));
});

var _Browser_pushUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.pushState({}, '', url);
		key();
	}));
});

var _Browser_replaceUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.replaceState({}, '', url);
		key();
	}));
});



// GLOBAL EVENTS


var _Browser_fakeNode = { addEventListener: function() {}, removeEventListener: function() {} };
var _Browser_doc = typeof document !== 'undefined' ? document : _Browser_fakeNode;
var _Browser_window = typeof window !== 'undefined' ? window : _Browser_fakeNode;

var _Browser_on = F3(function(node, eventName, sendToSelf)
{
	return _Scheduler_spawn(_Scheduler_binding(function(callback)
	{
		function handler(event)	{ _Scheduler_rawSpawn(sendToSelf(event)); }
		node.addEventListener(eventName, handler, _VirtualDom_passiveSupported && { passive: true });
		return function() { node.removeEventListener(eventName, handler); };
	}));
});

var _Browser_decodeEvent = F2(function(decoder, event)
{
	var result = _Json_runHelp(decoder, event);
	return $elm$core$Result$isOk(result) ? $elm$core$Maybe$Just(result.a) : $elm$core$Maybe$Nothing;
});



// PAGE VISIBILITY


function _Browser_visibilityInfo()
{
	return (typeof _VirtualDom_doc.hidden !== 'undefined')
		? { b1: 'hidden', bY: 'visibilitychange' }
		:
	(typeof _VirtualDom_doc.mozHidden !== 'undefined')
		? { b1: 'mozHidden', bY: 'mozvisibilitychange' }
		:
	(typeof _VirtualDom_doc.msHidden !== 'undefined')
		? { b1: 'msHidden', bY: 'msvisibilitychange' }
		:
	(typeof _VirtualDom_doc.webkitHidden !== 'undefined')
		? { b1: 'webkitHidden', bY: 'webkitvisibilitychange' }
		: { b1: 'hidden', bY: 'visibilitychange' };
}



// ANIMATION FRAMES


function _Browser_rAF()
{
	return _Scheduler_binding(function(callback)
	{
		var id = _Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(Date.now()));
		});

		return function() {
			_Browser_cancelAnimationFrame(id);
		};
	});
}


function _Browser_now()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(Date.now()));
	});
}



// DOM STUFF


function _Browser_withNode(id, doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			var node = document.getElementById(id);
			callback(node
				? _Scheduler_succeed(doStuff(node))
				: _Scheduler_fail($elm$browser$Browser$Dom$NotFound(id))
			);
		});
	});
}


function _Browser_withWindow(doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(doStuff()));
		});
	});
}


// FOCUS and BLUR


var _Browser_call = F2(function(functionName, id)
{
	return _Browser_withNode(id, function(node) {
		node[functionName]();
		return _Utils_Tuple0;
	});
});



// WINDOW VIEWPORT


function _Browser_getViewport()
{
	return {
		bB: _Browser_getScene(),
		bO: {
			ax: _Browser_window.pageXOffset,
			ay: _Browser_window.pageYOffset,
			bQ: _Browser_doc.documentElement.clientWidth,
			bc: _Browser_doc.documentElement.clientHeight
		}
	};
}

function _Browser_getScene()
{
	var body = _Browser_doc.body;
	var elem = _Browser_doc.documentElement;
	return {
		bQ: Math.max(body.scrollWidth, body.offsetWidth, elem.scrollWidth, elem.offsetWidth, elem.clientWidth),
		bc: Math.max(body.scrollHeight, body.offsetHeight, elem.scrollHeight, elem.offsetHeight, elem.clientHeight)
	};
}

var _Browser_setViewport = F2(function(x, y)
{
	return _Browser_withWindow(function()
	{
		_Browser_window.scroll(x, y);
		return _Utils_Tuple0;
	});
});



// ELEMENT VIEWPORT


function _Browser_getViewportOf(id)
{
	return _Browser_withNode(id, function(node)
	{
		return {
			bB: {
				bQ: node.scrollWidth,
				bc: node.scrollHeight
			},
			bO: {
				ax: node.scrollLeft,
				ay: node.scrollTop,
				bQ: node.clientWidth,
				bc: node.clientHeight
			}
		};
	});
}


var _Browser_setViewportOf = F3(function(id, x, y)
{
	return _Browser_withNode(id, function(node)
	{
		node.scrollLeft = x;
		node.scrollTop = y;
		return _Utils_Tuple0;
	});
});



// ELEMENT


function _Browser_getElement(id)
{
	return _Browser_withNode(id, function(node)
	{
		var rect = node.getBoundingClientRect();
		var x = _Browser_window.pageXOffset;
		var y = _Browser_window.pageYOffset;
		return {
			bB: _Browser_getScene(),
			bO: {
				ax: x,
				ay: y,
				bQ: _Browser_doc.documentElement.clientWidth,
				bc: _Browser_doc.documentElement.clientHeight
			},
			b$: {
				ax: x + rect.left,
				ay: y + rect.top,
				bQ: rect.width,
				bc: rect.height
			}
		};
	});
}



// LOAD and RELOAD


function _Browser_reload(skipCache)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		_VirtualDom_doc.location.reload(skipCache);
	}));
}

function _Browser_load(url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		try
		{
			_Browser_window.location = url;
		}
		catch(err)
		{
			// Only Firefox can throw a NS_ERROR_MALFORMED_URI exception here.
			// Other browsers reload the page, so let's be consistent about that.
			_VirtualDom_doc.location.reload(false);
		}
	}));
}



// SEND REQUEST

var _Http_toTask = F3(function(router, toTask, request)
{
	return _Scheduler_binding(function(callback)
	{
		function done(response) {
			callback(toTask(request.a9.a(response)));
		}

		var xhr = new XMLHttpRequest();
		xhr.addEventListener('error', function() { done($elm$http$Http$NetworkError_); });
		xhr.addEventListener('timeout', function() { done($elm$http$Http$Timeout_); });
		xhr.addEventListener('load', function() { done(_Http_toResponse(request.a9.b, xhr)); });
		$elm$core$Maybe$isJust(request.bL) && _Http_track(router, xhr, request.bL.a);

		try {
			xhr.open(request.b8, request.bN, true);
		} catch (e) {
			return done($elm$http$Http$BadUrl_(request.bN));
		}

		_Http_configureRequest(xhr, request);

		request.bV.a && xhr.setRequestHeader('Content-Type', request.bV.a);
		xhr.send(request.bV.b);

		return function() { xhr.c = true; xhr.abort(); };
	});
});


// CONFIGURE

function _Http_configureRequest(xhr, request)
{
	for (var headers = request.bb; headers.b; headers = headers.b) // WHILE_CONS
	{
		xhr.setRequestHeader(headers.a.a, headers.a.b);
	}
	xhr.timeout = request.cr.a || 0;
	xhr.responseType = request.a9.d;
	xhr.withCredentials = request.bS;
}


// RESPONSES

function _Http_toResponse(toBody, xhr)
{
	return A2(
		200 <= xhr.status && xhr.status < 300 ? $elm$http$Http$GoodStatus_ : $elm$http$Http$BadStatus_,
		_Http_toMetadata(xhr),
		toBody(xhr.response)
	);
}


// METADATA

function _Http_toMetadata(xhr)
{
	return {
		bN: xhr.responseURL,
		cn: xhr.status,
		co: xhr.statusText,
		bb: _Http_parseHeaders(xhr.getAllResponseHeaders())
	};
}


// HEADERS

function _Http_parseHeaders(rawHeaders)
{
	if (!rawHeaders)
	{
		return $elm$core$Dict$empty;
	}

	var headers = $elm$core$Dict$empty;
	var headerPairs = rawHeaders.split('\r\n');
	for (var i = headerPairs.length; i--; )
	{
		var headerPair = headerPairs[i];
		var index = headerPair.indexOf(': ');
		if (index > 0)
		{
			var key = headerPair.substring(0, index);
			var value = headerPair.substring(index + 2);

			headers = A3($elm$core$Dict$update, key, function(oldValue) {
				return $elm$core$Maybe$Just($elm$core$Maybe$isJust(oldValue)
					? value + ', ' + oldValue.a
					: value
				);
			}, headers);
		}
	}
	return headers;
}


// EXPECT

var _Http_expect = F3(function(type, toBody, toValue)
{
	return {
		$: 0,
		d: type,
		b: toBody,
		a: toValue
	};
});

var _Http_mapExpect = F2(function(func, expect)
{
	return {
		$: 0,
		d: expect.d,
		b: expect.b,
		a: function(x) { return func(expect.a(x)); }
	};
});

function _Http_toDataView(arrayBuffer)
{
	return new DataView(arrayBuffer);
}


// BODY and PARTS

var _Http_emptyBody = { $: 0 };
var _Http_pair = F2(function(a, b) { return { $: 0, a: a, b: b }; });

function _Http_toFormData(parts)
{
	for (var formData = new FormData(); parts.b; parts = parts.b) // WHILE_CONS
	{
		var part = parts.a;
		formData.append(part.a, part.b);
	}
	return formData;
}

var _Http_bytesToBlob = F2(function(mime, bytes)
{
	return new Blob([bytes], { type: mime });
});


// PROGRESS

function _Http_track(router, xhr, tracker)
{
	// TODO check out lengthComputable on loadstart event

	xhr.upload.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Sending({
			cl: event.loaded,
			bF: event.total
		}))));
	});
	xhr.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Receiving({
			ci: event.loaded,
			bF: event.lengthComputable ? $elm$core$Maybe$Just(event.total) : $elm$core$Maybe$Nothing
		}))));
	});
}

function _Url_percentEncode(string)
{
	return encodeURIComponent(string);
}

function _Url_percentDecode(string)
{
	try
	{
		return $elm$core$Maybe$Just(decodeURIComponent(string));
	}
	catch (e)
	{
		return $elm$core$Maybe$Nothing;
	}
}


function _Time_now(millisToPosix)
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(millisToPosix(Date.now())));
	});
}

var _Time_setInterval = F2(function(interval, task)
{
	return _Scheduler_binding(function(callback)
	{
		var id = setInterval(function() { _Scheduler_rawSpawn(task); }, interval);
		return function() { clearInterval(id); };
	});
});

function _Time_here()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(
			A2($elm$time$Time$customZone, -(new Date().getTimezoneOffset()), _List_Nil)
		));
	});
}


function _Time_getZoneName()
{
	return _Scheduler_binding(function(callback)
	{
		try
		{
			var name = $elm$time$Time$Name(Intl.DateTimeFormat().resolvedOptions().timeZone);
		}
		catch (e)
		{
			var name = $elm$time$Time$Offset(new Date().getTimezoneOffset());
		}
		callback(_Scheduler_succeed(name));
	});
}



// DECODER

var _File_decoder = _Json_decodePrim(function(value) {
	// NOTE: checks if `File` exists in case this is run on node
	return (typeof File !== 'undefined' && value instanceof File)
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FILE', value);
});


// METADATA

function _File_name(file) { return file.name; }
function _File_mime(file) { return file.type; }
function _File_size(file) { return file.size; }

function _File_lastModified(file)
{
	return $elm$time$Time$millisToPosix(file.lastModified);
}


// DOWNLOAD

var _File_downloadNode;

function _File_getDownloadNode()
{
	return _File_downloadNode || (_File_downloadNode = document.createElement('a'));
}

var _File_download = F3(function(name, mime, content)
{
	return _Scheduler_binding(function(callback)
	{
		var blob = new Blob([content], {type: mime});

		// for IE10+
		if (navigator.msSaveOrOpenBlob)
		{
			navigator.msSaveOrOpenBlob(blob, name);
			return;
		}

		// for HTML5
		var node = _File_getDownloadNode();
		var objectUrl = URL.createObjectURL(blob);
		node.href = objectUrl;
		node.download = name;
		_File_click(node);
		URL.revokeObjectURL(objectUrl);
	});
});

function _File_downloadUrl(href)
{
	return _Scheduler_binding(function(callback)
	{
		var node = _File_getDownloadNode();
		node.href = href;
		node.download = '';
		node.origin === location.origin || (node.target = '_blank');
		_File_click(node);
	});
}


// IE COMPATIBILITY

function _File_makeBytesSafeForInternetExplorer(bytes)
{
	// only needed by IE10 and IE11 to fix https://github.com/elm/file/issues/10
	// all other browsers can just run `new Blob([bytes])` directly with no problem
	//
	return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

function _File_click(node)
{
	// only needed by IE10 and IE11 to fix https://github.com/elm/file/issues/11
	// all other browsers have MouseEvent and do not need this conditional stuff
	//
	if (typeof MouseEvent === 'function')
	{
		node.dispatchEvent(new MouseEvent('click'));
	}
	else
	{
		var event = document.createEvent('MouseEvents');
		event.initMouseEvent('click', true, true, window, 0, 0, 0, 0, 0, false, false, false, false, 0, null);
		document.body.appendChild(node);
		node.dispatchEvent(event);
		document.body.removeChild(node);
	}
}


// UPLOAD

var _File_node;

function _File_uploadOne(mimes)
{
	return _Scheduler_binding(function(callback)
	{
		_File_node = document.createElement('input');
		_File_node.type = 'file';
		_File_node.accept = A2($elm$core$String$join, ',', mimes);
		_File_node.addEventListener('change', function(event)
		{
			callback(_Scheduler_succeed(event.target.files[0]));
		});
		_File_click(_File_node);
	});
}

function _File_uploadOneOrMore(mimes)
{
	return _Scheduler_binding(function(callback)
	{
		_File_node = document.createElement('input');
		_File_node.type = 'file';
		_File_node.multiple = true;
		_File_node.accept = A2($elm$core$String$join, ',', mimes);
		_File_node.addEventListener('change', function(event)
		{
			var elmFiles = _List_fromArray(event.target.files);
			callback(_Scheduler_succeed(_Utils_Tuple2(elmFiles.a, elmFiles.b)));
		});
		_File_click(_File_node);
	});
}


// CONTENT

function _File_toString(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(reader.result));
		});
		reader.readAsText(blob);
		return function() { reader.abort(); };
	});
}

function _File_toBytes(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(new DataView(reader.result)));
		});
		reader.readAsArrayBuffer(blob);
		return function() { reader.abort(); };
	});
}

function _File_toUrl(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(reader.result));
		});
		reader.readAsDataURL(blob);
		return function() { reader.abort(); };
	});
}




var _Bitwise_and = F2(function(a, b)
{
	return a & b;
});

var _Bitwise_or = F2(function(a, b)
{
	return a | b;
});

var _Bitwise_xor = F2(function(a, b)
{
	return a ^ b;
});

function _Bitwise_complement(a)
{
	return ~a;
};

var _Bitwise_shiftLeftBy = F2(function(offset, a)
{
	return a << offset;
});

var _Bitwise_shiftRightBy = F2(function(offset, a)
{
	return a >> offset;
});

var _Bitwise_shiftRightZfBy = F2(function(offset, a)
{
	return a >>> offset;
});
var $author$project$Main$Ignore = {$: 0};
var $elm$core$Maybe$Just = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Maybe$Nothing = {$: 1};
var $elm$core$Basics$EQ = 1;
var $elm$core$Basics$GT = 2;
var $elm$core$Basics$LT = 0;
var $elm$core$List$cons = _List_cons;
var $elm$core$Dict$foldr = F3(
	function (func, acc, t) {
		foldr:
		while (true) {
			if (t.$ === -2) {
				return acc;
			} else {
				var key = t.b;
				var value = t.c;
				var left = t.d;
				var right = t.e;
				var $temp$func = func,
					$temp$acc = A3(
					func,
					key,
					value,
					A3($elm$core$Dict$foldr, func, acc, right)),
					$temp$t = left;
				func = $temp$func;
				acc = $temp$acc;
				t = $temp$t;
				continue foldr;
			}
		}
	});
var $elm$core$Dict$toList = function (dict) {
	return A3(
		$elm$core$Dict$foldr,
		F3(
			function (key, value, list) {
				return A2(
					$elm$core$List$cons,
					_Utils_Tuple2(key, value),
					list);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Dict$keys = function (dict) {
	return A3(
		$elm$core$Dict$foldr,
		F3(
			function (key, value, keyList) {
				return A2($elm$core$List$cons, key, keyList);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Set$toList = function (_v0) {
	var dict = _v0;
	return $elm$core$Dict$keys(dict);
};
var $elm$core$Elm$JsArray$foldr = _JsArray_foldr;
var $elm$core$Array$foldr = F3(
	function (func, baseCase, _v0) {
		var tree = _v0.c;
		var tail = _v0.d;
		var helper = F2(
			function (node, acc) {
				if (!node.$) {
					var subTree = node.a;
					return A3($elm$core$Elm$JsArray$foldr, helper, acc, subTree);
				} else {
					var values = node.a;
					return A3($elm$core$Elm$JsArray$foldr, func, acc, values);
				}
			});
		return A3(
			$elm$core$Elm$JsArray$foldr,
			helper,
			A3($elm$core$Elm$JsArray$foldr, func, baseCase, tail),
			tree);
	});
var $elm$core$Array$toList = function (array) {
	return A3($elm$core$Array$foldr, $elm$core$List$cons, _List_Nil, array);
};
var $elm$core$Result$Err = function (a) {
	return {$: 1, a: a};
};
var $elm$json$Json$Decode$Failure = F2(
	function (a, b) {
		return {$: 3, a: a, b: b};
	});
var $elm$json$Json$Decode$Field = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$json$Json$Decode$Index = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $elm$core$Result$Ok = function (a) {
	return {$: 0, a: a};
};
var $elm$json$Json$Decode$OneOf = function (a) {
	return {$: 2, a: a};
};
var $elm$core$Basics$False = 1;
var $elm$core$Basics$add = _Basics_add;
var $elm$core$String$all = _String_all;
var $elm$core$Basics$and = _Basics_and;
var $elm$core$Basics$append = _Utils_append;
var $elm$json$Json$Encode$encode = _Json_encode;
var $elm$core$String$fromInt = _String_fromNumber;
var $elm$core$String$join = F2(
	function (sep, chunks) {
		return A2(
			_String_join,
			sep,
			_List_toArray(chunks));
	});
var $elm$core$String$split = F2(
	function (sep, string) {
		return _List_fromArray(
			A2(_String_split, sep, string));
	});
var $elm$json$Json$Decode$indent = function (str) {
	return A2(
		$elm$core$String$join,
		'\n    ',
		A2($elm$core$String$split, '\n', str));
};
var $elm$core$List$foldl = F3(
	function (func, acc, list) {
		foldl:
		while (true) {
			if (!list.b) {
				return acc;
			} else {
				var x = list.a;
				var xs = list.b;
				var $temp$func = func,
					$temp$acc = A2(func, x, acc),
					$temp$list = xs;
				func = $temp$func;
				acc = $temp$acc;
				list = $temp$list;
				continue foldl;
			}
		}
	});
var $elm$core$List$length = function (xs) {
	return A3(
		$elm$core$List$foldl,
		F2(
			function (_v0, i) {
				return i + 1;
			}),
		0,
		xs);
};
var $elm$core$List$map2 = _List_map2;
var $elm$core$Basics$le = _Utils_le;
var $elm$core$Basics$sub = _Basics_sub;
var $elm$core$List$rangeHelp = F3(
	function (lo, hi, list) {
		rangeHelp:
		while (true) {
			if (_Utils_cmp(lo, hi) < 1) {
				var $temp$lo = lo,
					$temp$hi = hi - 1,
					$temp$list = A2($elm$core$List$cons, hi, list);
				lo = $temp$lo;
				hi = $temp$hi;
				list = $temp$list;
				continue rangeHelp;
			} else {
				return list;
			}
		}
	});
var $elm$core$List$range = F2(
	function (lo, hi) {
		return A3($elm$core$List$rangeHelp, lo, hi, _List_Nil);
	});
var $elm$core$List$indexedMap = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$map2,
			f,
			A2(
				$elm$core$List$range,
				0,
				$elm$core$List$length(xs) - 1),
			xs);
	});
var $elm$core$Char$toCode = _Char_toCode;
var $elm$core$Char$isLower = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (97 <= code) && (code <= 122);
};
var $elm$core$Char$isUpper = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 90) && (65 <= code);
};
var $elm$core$Basics$or = _Basics_or;
var $elm$core$Char$isAlpha = function (_char) {
	return $elm$core$Char$isLower(_char) || $elm$core$Char$isUpper(_char);
};
var $elm$core$Char$isDigit = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 57) && (48 <= code);
};
var $elm$core$Char$isAlphaNum = function (_char) {
	return $elm$core$Char$isLower(_char) || ($elm$core$Char$isUpper(_char) || $elm$core$Char$isDigit(_char));
};
var $elm$core$List$reverse = function (list) {
	return A3($elm$core$List$foldl, $elm$core$List$cons, _List_Nil, list);
};
var $elm$core$String$uncons = _String_uncons;
var $elm$json$Json$Decode$errorOneOf = F2(
	function (i, error) {
		return '\n\n(' + ($elm$core$String$fromInt(i + 1) + (') ' + $elm$json$Json$Decode$indent(
			$elm$json$Json$Decode$errorToString(error))));
	});
var $elm$json$Json$Decode$errorToString = function (error) {
	return A2($elm$json$Json$Decode$errorToStringHelp, error, _List_Nil);
};
var $elm$json$Json$Decode$errorToStringHelp = F2(
	function (error, context) {
		errorToStringHelp:
		while (true) {
			switch (error.$) {
				case 0:
					var f = error.a;
					var err = error.b;
					var isSimple = function () {
						var _v1 = $elm$core$String$uncons(f);
						if (_v1.$ === 1) {
							return false;
						} else {
							var _v2 = _v1.a;
							var _char = _v2.a;
							var rest = _v2.b;
							return $elm$core$Char$isAlpha(_char) && A2($elm$core$String$all, $elm$core$Char$isAlphaNum, rest);
						}
					}();
					var fieldName = isSimple ? ('.' + f) : ('[\'' + (f + '\']'));
					var $temp$error = err,
						$temp$context = A2($elm$core$List$cons, fieldName, context);
					error = $temp$error;
					context = $temp$context;
					continue errorToStringHelp;
				case 1:
					var i = error.a;
					var err = error.b;
					var indexName = '[' + ($elm$core$String$fromInt(i) + ']');
					var $temp$error = err,
						$temp$context = A2($elm$core$List$cons, indexName, context);
					error = $temp$error;
					context = $temp$context;
					continue errorToStringHelp;
				case 2:
					var errors = error.a;
					if (!errors.b) {
						return 'Ran into a Json.Decode.oneOf with no possibilities' + function () {
							if (!context.b) {
								return '!';
							} else {
								return ' at json' + A2(
									$elm$core$String$join,
									'',
									$elm$core$List$reverse(context));
							}
						}();
					} else {
						if (!errors.b.b) {
							var err = errors.a;
							var $temp$error = err,
								$temp$context = context;
							error = $temp$error;
							context = $temp$context;
							continue errorToStringHelp;
						} else {
							var starter = function () {
								if (!context.b) {
									return 'Json.Decode.oneOf';
								} else {
									return 'The Json.Decode.oneOf at json' + A2(
										$elm$core$String$join,
										'',
										$elm$core$List$reverse(context));
								}
							}();
							var introduction = starter + (' failed in the following ' + ($elm$core$String$fromInt(
								$elm$core$List$length(errors)) + ' ways:'));
							return A2(
								$elm$core$String$join,
								'\n\n',
								A2(
									$elm$core$List$cons,
									introduction,
									A2($elm$core$List$indexedMap, $elm$json$Json$Decode$errorOneOf, errors)));
						}
					}
				default:
					var msg = error.a;
					var json = error.b;
					var introduction = function () {
						if (!context.b) {
							return 'Problem with the given value:\n\n';
						} else {
							return 'Problem with the value at json' + (A2(
								$elm$core$String$join,
								'',
								$elm$core$List$reverse(context)) + ':\n\n    ');
						}
					}();
					return introduction + ($elm$json$Json$Decode$indent(
						A2($elm$json$Json$Encode$encode, 4, json)) + ('\n\n' + msg));
			}
		}
	});
var $elm$core$Array$branchFactor = 32;
var $elm$core$Array$Array_elm_builtin = F4(
	function (a, b, c, d) {
		return {$: 0, a: a, b: b, c: c, d: d};
	});
var $elm$core$Elm$JsArray$empty = _JsArray_empty;
var $elm$core$Basics$ceiling = _Basics_ceiling;
var $elm$core$Basics$fdiv = _Basics_fdiv;
var $elm$core$Basics$logBase = F2(
	function (base, number) {
		return _Basics_log(number) / _Basics_log(base);
	});
var $elm$core$Basics$toFloat = _Basics_toFloat;
var $elm$core$Array$shiftStep = $elm$core$Basics$ceiling(
	A2($elm$core$Basics$logBase, 2, $elm$core$Array$branchFactor));
var $elm$core$Array$empty = A4($elm$core$Array$Array_elm_builtin, 0, $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, $elm$core$Elm$JsArray$empty);
var $elm$core$Elm$JsArray$initialize = _JsArray_initialize;
var $elm$core$Array$Leaf = function (a) {
	return {$: 1, a: a};
};
var $elm$core$Basics$apL = F2(
	function (f, x) {
		return f(x);
	});
var $elm$core$Basics$apR = F2(
	function (x, f) {
		return f(x);
	});
var $elm$core$Basics$eq = _Utils_equal;
var $elm$core$Basics$floor = _Basics_floor;
var $elm$core$Elm$JsArray$length = _JsArray_length;
var $elm$core$Basics$gt = _Utils_gt;
var $elm$core$Basics$max = F2(
	function (x, y) {
		return (_Utils_cmp(x, y) > 0) ? x : y;
	});
var $elm$core$Basics$mul = _Basics_mul;
var $elm$core$Array$SubTree = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Elm$JsArray$initializeFromList = _JsArray_initializeFromList;
var $elm$core$Array$compressNodes = F2(
	function (nodes, acc) {
		compressNodes:
		while (true) {
			var _v0 = A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodes);
			var node = _v0.a;
			var remainingNodes = _v0.b;
			var newAcc = A2(
				$elm$core$List$cons,
				$elm$core$Array$SubTree(node),
				acc);
			if (!remainingNodes.b) {
				return $elm$core$List$reverse(newAcc);
			} else {
				var $temp$nodes = remainingNodes,
					$temp$acc = newAcc;
				nodes = $temp$nodes;
				acc = $temp$acc;
				continue compressNodes;
			}
		}
	});
var $elm$core$Tuple$first = function (_v0) {
	var x = _v0.a;
	return x;
};
var $elm$core$Array$treeFromBuilder = F2(
	function (nodeList, nodeListSize) {
		treeFromBuilder:
		while (true) {
			var newNodeSize = $elm$core$Basics$ceiling(nodeListSize / $elm$core$Array$branchFactor);
			if (newNodeSize === 1) {
				return A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodeList).a;
			} else {
				var $temp$nodeList = A2($elm$core$Array$compressNodes, nodeList, _List_Nil),
					$temp$nodeListSize = newNodeSize;
				nodeList = $temp$nodeList;
				nodeListSize = $temp$nodeListSize;
				continue treeFromBuilder;
			}
		}
	});
var $elm$core$Array$builderToArray = F2(
	function (reverseNodeList, builder) {
		if (!builder.g) {
			return A4(
				$elm$core$Array$Array_elm_builtin,
				$elm$core$Elm$JsArray$length(builder.i),
				$elm$core$Array$shiftStep,
				$elm$core$Elm$JsArray$empty,
				builder.i);
		} else {
			var treeLen = builder.g * $elm$core$Array$branchFactor;
			var depth = $elm$core$Basics$floor(
				A2($elm$core$Basics$logBase, $elm$core$Array$branchFactor, treeLen - 1));
			var correctNodeList = reverseNodeList ? $elm$core$List$reverse(builder.j) : builder.j;
			var tree = A2($elm$core$Array$treeFromBuilder, correctNodeList, builder.g);
			return A4(
				$elm$core$Array$Array_elm_builtin,
				$elm$core$Elm$JsArray$length(builder.i) + treeLen,
				A2($elm$core$Basics$max, 5, depth * $elm$core$Array$shiftStep),
				tree,
				builder.i);
		}
	});
var $elm$core$Basics$idiv = _Basics_idiv;
var $elm$core$Basics$lt = _Utils_lt;
var $elm$core$Array$initializeHelp = F5(
	function (fn, fromIndex, len, nodeList, tail) {
		initializeHelp:
		while (true) {
			if (fromIndex < 0) {
				return A2(
					$elm$core$Array$builderToArray,
					false,
					{j: nodeList, g: (len / $elm$core$Array$branchFactor) | 0, i: tail});
			} else {
				var leaf = $elm$core$Array$Leaf(
					A3($elm$core$Elm$JsArray$initialize, $elm$core$Array$branchFactor, fromIndex, fn));
				var $temp$fn = fn,
					$temp$fromIndex = fromIndex - $elm$core$Array$branchFactor,
					$temp$len = len,
					$temp$nodeList = A2($elm$core$List$cons, leaf, nodeList),
					$temp$tail = tail;
				fn = $temp$fn;
				fromIndex = $temp$fromIndex;
				len = $temp$len;
				nodeList = $temp$nodeList;
				tail = $temp$tail;
				continue initializeHelp;
			}
		}
	});
var $elm$core$Basics$remainderBy = _Basics_remainderBy;
var $elm$core$Array$initialize = F2(
	function (len, fn) {
		if (len <= 0) {
			return $elm$core$Array$empty;
		} else {
			var tailLen = len % $elm$core$Array$branchFactor;
			var tail = A3($elm$core$Elm$JsArray$initialize, tailLen, len - tailLen, fn);
			var initialFromIndex = (len - tailLen) - $elm$core$Array$branchFactor;
			return A5($elm$core$Array$initializeHelp, fn, initialFromIndex, len, _List_Nil, tail);
		}
	});
var $elm$core$Basics$True = 0;
var $elm$core$Result$isOk = function (result) {
	if (!result.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$json$Json$Decode$map = _Json_map1;
var $elm$json$Json$Decode$map2 = _Json_map2;
var $elm$json$Json$Decode$succeed = _Json_succeed;
var $elm$virtual_dom$VirtualDom$toHandlerInt = function (handler) {
	switch (handler.$) {
		case 0:
			return 0;
		case 1:
			return 1;
		case 2:
			return 2;
		default:
			return 3;
	}
};
var $elm$browser$Browser$External = function (a) {
	return {$: 1, a: a};
};
var $elm$browser$Browser$Internal = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Basics$identity = function (x) {
	return x;
};
var $elm$browser$Browser$Dom$NotFound = $elm$core$Basics$identity;
var $elm$url$Url$Http = 0;
var $elm$url$Url$Https = 1;
var $elm$url$Url$Url = F6(
	function (protocol, host, port_, path, query, fragment) {
		return {ba: fragment, bd: host, cf: path, br: port_, bv: protocol, ch: query};
	});
var $elm$core$String$contains = _String_contains;
var $elm$core$String$length = _String_length;
var $elm$core$String$slice = _String_slice;
var $elm$core$String$dropLeft = F2(
	function (n, string) {
		return (n < 1) ? string : A3(
			$elm$core$String$slice,
			n,
			$elm$core$String$length(string),
			string);
	});
var $elm$core$String$indexes = _String_indexes;
var $elm$core$String$isEmpty = function (string) {
	return string === '';
};
var $elm$core$String$left = F2(
	function (n, string) {
		return (n < 1) ? '' : A3($elm$core$String$slice, 0, n, string);
	});
var $elm$core$String$toInt = _String_toInt;
var $elm$url$Url$chompBeforePath = F5(
	function (protocol, path, params, frag, str) {
		if ($elm$core$String$isEmpty(str) || A2($elm$core$String$contains, '@', str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, ':', str);
			if (!_v0.b) {
				return $elm$core$Maybe$Just(
					A6($elm$url$Url$Url, protocol, str, $elm$core$Maybe$Nothing, path, params, frag));
			} else {
				if (!_v0.b.b) {
					var i = _v0.a;
					var _v1 = $elm$core$String$toInt(
						A2($elm$core$String$dropLeft, i + 1, str));
					if (_v1.$ === 1) {
						return $elm$core$Maybe$Nothing;
					} else {
						var port_ = _v1;
						return $elm$core$Maybe$Just(
							A6(
								$elm$url$Url$Url,
								protocol,
								A2($elm$core$String$left, i, str),
								port_,
								path,
								params,
								frag));
					}
				} else {
					return $elm$core$Maybe$Nothing;
				}
			}
		}
	});
var $elm$url$Url$chompBeforeQuery = F4(
	function (protocol, params, frag, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '/', str);
			if (!_v0.b) {
				return A5($elm$url$Url$chompBeforePath, protocol, '/', params, frag, str);
			} else {
				var i = _v0.a;
				return A5(
					$elm$url$Url$chompBeforePath,
					protocol,
					A2($elm$core$String$dropLeft, i, str),
					params,
					frag,
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$url$Url$chompBeforeFragment = F3(
	function (protocol, frag, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '?', str);
			if (!_v0.b) {
				return A4($elm$url$Url$chompBeforeQuery, protocol, $elm$core$Maybe$Nothing, frag, str);
			} else {
				var i = _v0.a;
				return A4(
					$elm$url$Url$chompBeforeQuery,
					protocol,
					$elm$core$Maybe$Just(
						A2($elm$core$String$dropLeft, i + 1, str)),
					frag,
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$url$Url$chompAfterProtocol = F2(
	function (protocol, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '#', str);
			if (!_v0.b) {
				return A3($elm$url$Url$chompBeforeFragment, protocol, $elm$core$Maybe$Nothing, str);
			} else {
				var i = _v0.a;
				return A3(
					$elm$url$Url$chompBeforeFragment,
					protocol,
					$elm$core$Maybe$Just(
						A2($elm$core$String$dropLeft, i + 1, str)),
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$core$String$startsWith = _String_startsWith;
var $elm$url$Url$fromString = function (str) {
	return A2($elm$core$String$startsWith, 'http://', str) ? A2(
		$elm$url$Url$chompAfterProtocol,
		0,
		A2($elm$core$String$dropLeft, 7, str)) : (A2($elm$core$String$startsWith, 'https://', str) ? A2(
		$elm$url$Url$chompAfterProtocol,
		1,
		A2($elm$core$String$dropLeft, 8, str)) : $elm$core$Maybe$Nothing);
};
var $elm$core$Basics$never = function (_v0) {
	never:
	while (true) {
		var nvr = _v0;
		var $temp$_v0 = nvr;
		_v0 = $temp$_v0;
		continue never;
	}
};
var $elm$core$Task$Perform = $elm$core$Basics$identity;
var $elm$core$Task$succeed = _Scheduler_succeed;
var $elm$core$Task$init = $elm$core$Task$succeed(0);
var $elm$core$List$foldrHelper = F4(
	function (fn, acc, ctr, ls) {
		if (!ls.b) {
			return acc;
		} else {
			var a = ls.a;
			var r1 = ls.b;
			if (!r1.b) {
				return A2(fn, a, acc);
			} else {
				var b = r1.a;
				var r2 = r1.b;
				if (!r2.b) {
					return A2(
						fn,
						a,
						A2(fn, b, acc));
				} else {
					var c = r2.a;
					var r3 = r2.b;
					if (!r3.b) {
						return A2(
							fn,
							a,
							A2(
								fn,
								b,
								A2(fn, c, acc)));
					} else {
						var d = r3.a;
						var r4 = r3.b;
						var res = (ctr > 500) ? A3(
							$elm$core$List$foldl,
							fn,
							acc,
							$elm$core$List$reverse(r4)) : A4($elm$core$List$foldrHelper, fn, acc, ctr + 1, r4);
						return A2(
							fn,
							a,
							A2(
								fn,
								b,
								A2(
									fn,
									c,
									A2(fn, d, res))));
					}
				}
			}
		}
	});
var $elm$core$List$foldr = F3(
	function (fn, acc, ls) {
		return A4($elm$core$List$foldrHelper, fn, acc, 0, ls);
	});
var $elm$core$List$map = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$foldr,
			F2(
				function (x, acc) {
					return A2(
						$elm$core$List$cons,
						f(x),
						acc);
				}),
			_List_Nil,
			xs);
	});
var $elm$core$Task$andThen = _Scheduler_andThen;
var $elm$core$Task$map = F2(
	function (func, taskA) {
		return A2(
			$elm$core$Task$andThen,
			function (a) {
				return $elm$core$Task$succeed(
					func(a));
			},
			taskA);
	});
var $elm$core$Task$map2 = F3(
	function (func, taskA, taskB) {
		return A2(
			$elm$core$Task$andThen,
			function (a) {
				return A2(
					$elm$core$Task$andThen,
					function (b) {
						return $elm$core$Task$succeed(
							A2(func, a, b));
					},
					taskB);
			},
			taskA);
	});
var $elm$core$Task$sequence = function (tasks) {
	return A3(
		$elm$core$List$foldr,
		$elm$core$Task$map2($elm$core$List$cons),
		$elm$core$Task$succeed(_List_Nil),
		tasks);
};
var $elm$core$Platform$sendToApp = _Platform_sendToApp;
var $elm$core$Task$spawnCmd = F2(
	function (router, _v0) {
		var task = _v0;
		return _Scheduler_spawn(
			A2(
				$elm$core$Task$andThen,
				$elm$core$Platform$sendToApp(router),
				task));
	});
var $elm$core$Task$onEffects = F3(
	function (router, commands, state) {
		return A2(
			$elm$core$Task$map,
			function (_v0) {
				return 0;
			},
			$elm$core$Task$sequence(
				A2(
					$elm$core$List$map,
					$elm$core$Task$spawnCmd(router),
					commands)));
	});
var $elm$core$Task$onSelfMsg = F3(
	function (_v0, _v1, _v2) {
		return $elm$core$Task$succeed(0);
	});
var $elm$core$Task$cmdMap = F2(
	function (tagger, _v0) {
		var task = _v0;
		return A2($elm$core$Task$map, tagger, task);
	});
_Platform_effectManagers['Task'] = _Platform_createManager($elm$core$Task$init, $elm$core$Task$onEffects, $elm$core$Task$onSelfMsg, $elm$core$Task$cmdMap);
var $elm$core$Task$command = _Platform_leaf('Task');
var $elm$core$Task$perform = F2(
	function (toMessage, task) {
		return $elm$core$Task$command(
			A2($elm$core$Task$map, toMessage, task));
	});
var $elm$browser$Browser$application = _Browser_application;
var $author$project$Main$Model = F2(
	function (nav, state) {
		return {aP: nav, o: state};
	});
var $author$project$Main$Navigation = F2(
	function (key, basePath) {
		return {a0: basePath, bf: key};
	});
var $author$project$Main$StateUrlFetched = function (a) {
	return {$: 58, a: a};
};
var $elm$json$Json$Decode$decodeValue = _Json_run;
var $author$project$Main$ElevationProfileTab = 0;
var $author$project$Main$NotLoaded = {$: 0};
var $author$project$Main$StaticView = 1;
var $author$project$Main$FromZero = {$: 0};
var $author$project$Main$defaultDistanceDetail = 1;
var $author$project$Main$defaultSpacing = 25;
var $author$project$Main$defaultCuesheetOptions = {A: $author$project$Main$defaultDistanceDetail, m: $author$project$Main$defaultSpacing, t: 1000, H: false, h: $author$project$Main$FromZero};
var $author$project$Main$EquidistantMode = 0;
var $author$project$Main$defaultElevationProfileOptions = {J: 0, M: $elm$core$Maybe$Nothing, N: false, W: 15, O: 500, X: 1.0, B: 5000, C: 2000, G: false, aa: 1, l: _List_Nil, ac: 200, ad: 1};
var $elm$core$Dict$RBEmpty_elm_builtin = {$: -2};
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $author$project$Main$defaultState = {K: 0, z: false, e: $author$project$Main$defaultCuesheetOptions, a: $author$project$Main$defaultElevationProfileOptions, d: $elm$core$Dict$empty, ag: $elm$core$Maybe$Nothing, Y: $elm$core$Maybe$Nothing, Q: $elm$core$Dict$empty, w: 100, cg: $elm$core$Maybe$Nothing, ai: $elm$core$Maybe$Nothing, S: false, T: true, _: true, I: $elm$core$Maybe$Nothing, ab: $elm$core$Maybe$Nothing, y: false, U: 60, b: $author$project$Main$NotLoaded, q: 1};
var $elm$http$Http$BadStatus_ = F2(
	function (a, b) {
		return {$: 3, a: a, b: b};
	});
var $elm$http$Http$BadUrl_ = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$GoodStatus_ = F2(
	function (a, b) {
		return {$: 4, a: a, b: b};
	});
var $elm$http$Http$NetworkError_ = {$: 2};
var $elm$http$Http$Receiving = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$Sending = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$Timeout_ = {$: 1};
var $elm$core$Maybe$isJust = function (maybe) {
	if (!maybe.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Platform$sendToSelf = _Platform_sendToSelf;
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$get = F2(
	function (targetKey, dict) {
		get:
		while (true) {
			if (dict.$ === -2) {
				return $elm$core$Maybe$Nothing;
			} else {
				var key = dict.b;
				var value = dict.c;
				var left = dict.d;
				var right = dict.e;
				var _v1 = A2($elm$core$Basics$compare, targetKey, key);
				switch (_v1) {
					case 0:
						var $temp$targetKey = targetKey,
							$temp$dict = left;
						targetKey = $temp$targetKey;
						dict = $temp$dict;
						continue get;
					case 1:
						return $elm$core$Maybe$Just(value);
					default:
						var $temp$targetKey = targetKey,
							$temp$dict = right;
						targetKey = $temp$targetKey;
						dict = $temp$dict;
						continue get;
				}
			}
		}
	});
var $elm$core$Dict$Black = 1;
var $elm$core$Dict$RBNode_elm_builtin = F5(
	function (a, b, c, d, e) {
		return {$: -1, a: a, b: b, c: c, d: d, e: e};
	});
var $elm$core$Dict$Red = 0;
var $elm$core$Dict$balance = F5(
	function (color, key, value, left, right) {
		if ((right.$ === -1) && (!right.a)) {
			var _v1 = right.a;
			var rK = right.b;
			var rV = right.c;
			var rLeft = right.d;
			var rRight = right.e;
			if ((left.$ === -1) && (!left.a)) {
				var _v3 = left.a;
				var lK = left.b;
				var lV = left.c;
				var lLeft = left.d;
				var lRight = left.e;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					0,
					key,
					value,
					A5($elm$core$Dict$RBNode_elm_builtin, 1, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					color,
					rK,
					rV,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, left, rLeft),
					rRight);
			}
		} else {
			if ((((left.$ === -1) && (!left.a)) && (left.d.$ === -1)) && (!left.d.a)) {
				var _v5 = left.a;
				var lK = left.b;
				var lV = left.c;
				var _v6 = left.d;
				var _v7 = _v6.a;
				var llK = _v6.b;
				var llV = _v6.c;
				var llLeft = _v6.d;
				var llRight = _v6.e;
				var lRight = left.e;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					0,
					lK,
					lV,
					A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 1, key, value, lRight, right));
			} else {
				return A5($elm$core$Dict$RBNode_elm_builtin, color, key, value, left, right);
			}
		}
	});
var $elm$core$Dict$insertHelp = F3(
	function (key, value, dict) {
		if (dict.$ === -2) {
			return A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin);
		} else {
			var nColor = dict.a;
			var nKey = dict.b;
			var nValue = dict.c;
			var nLeft = dict.d;
			var nRight = dict.e;
			var _v1 = A2($elm$core$Basics$compare, key, nKey);
			switch (_v1) {
				case 0:
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						A3($elm$core$Dict$insertHelp, key, value, nLeft),
						nRight);
				case 1:
					return A5($elm$core$Dict$RBNode_elm_builtin, nColor, nKey, value, nLeft, nRight);
				default:
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						nLeft,
						A3($elm$core$Dict$insertHelp, key, value, nRight));
			}
		}
	});
var $elm$core$Dict$insert = F3(
	function (key, value, dict) {
		var _v0 = A3($elm$core$Dict$insertHelp, key, value, dict);
		if ((_v0.$ === -1) && (!_v0.a)) {
			var _v1 = _v0.a;
			var k = _v0.b;
			var v = _v0.c;
			var l = _v0.d;
			var r = _v0.e;
			return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
		} else {
			var x = _v0;
			return x;
		}
	});
var $elm$core$Dict$getMin = function (dict) {
	getMin:
	while (true) {
		if ((dict.$ === -1) && (dict.d.$ === -1)) {
			var left = dict.d;
			var $temp$dict = left;
			dict = $temp$dict;
			continue getMin;
		} else {
			return dict;
		}
	}
};
var $elm$core$Dict$moveRedLeft = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.e.d.$ === -1) && (!dict.e.d.a)) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var lLeft = _v1.d;
			var lRight = _v1.e;
			var _v2 = dict.e;
			var rClr = _v2.a;
			var rK = _v2.b;
			var rV = _v2.c;
			var rLeft = _v2.d;
			var _v3 = rLeft.a;
			var rlK = rLeft.b;
			var rlV = rLeft.c;
			var rlL = rLeft.d;
			var rlR = rLeft.e;
			var rRight = _v2.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				0,
				rlK,
				rlV,
				A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					rlL),
				A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rlR, rRight));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v4 = dict.d;
			var lClr = _v4.a;
			var lK = _v4.b;
			var lV = _v4.c;
			var lLeft = _v4.d;
			var lRight = _v4.e;
			var _v5 = dict.e;
			var rClr = _v5.a;
			var rK = _v5.b;
			var rV = _v5.c;
			var rLeft = _v5.d;
			var rRight = _v5.e;
			if (clr === 1) {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$moveRedRight = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.d.d.$ === -1) && (!dict.d.d.a)) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var _v2 = _v1.d;
			var _v3 = _v2.a;
			var llK = _v2.b;
			var llV = _v2.c;
			var llLeft = _v2.d;
			var llRight = _v2.e;
			var lRight = _v1.e;
			var _v4 = dict.e;
			var rClr = _v4.a;
			var rK = _v4.b;
			var rV = _v4.c;
			var rLeft = _v4.d;
			var rRight = _v4.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				0,
				lK,
				lV,
				A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
				A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					lRight,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight)));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v5 = dict.d;
			var lClr = _v5.a;
			var lK = _v5.b;
			var lV = _v5.c;
			var lLeft = _v5.d;
			var lRight = _v5.e;
			var _v6 = dict.e;
			var rClr = _v6.a;
			var rK = _v6.b;
			var rV = _v6.c;
			var rLeft = _v6.d;
			var rRight = _v6.e;
			if (clr === 1) {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$removeHelpPrepEQGT = F7(
	function (targetKey, dict, color, key, value, left, right) {
		if ((left.$ === -1) && (!left.a)) {
			var _v1 = left.a;
			var lK = left.b;
			var lV = left.c;
			var lLeft = left.d;
			var lRight = left.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				lK,
				lV,
				lLeft,
				A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, lRight, right));
		} else {
			_v2$2:
			while (true) {
				if ((right.$ === -1) && (right.a === 1)) {
					if (right.d.$ === -1) {
						if (right.d.a === 1) {
							var _v3 = right.a;
							var _v4 = right.d;
							var _v5 = _v4.a;
							return $elm$core$Dict$moveRedRight(dict);
						} else {
							break _v2$2;
						}
					} else {
						var _v6 = right.a;
						var _v7 = right.d;
						return $elm$core$Dict$moveRedRight(dict);
					}
				} else {
					break _v2$2;
				}
			}
			return dict;
		}
	});
var $elm$core$Dict$removeMin = function (dict) {
	if ((dict.$ === -1) && (dict.d.$ === -1)) {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var lColor = left.a;
		var lLeft = left.d;
		var right = dict.e;
		if (lColor === 1) {
			if ((lLeft.$ === -1) && (!lLeft.a)) {
				var _v3 = lLeft.a;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					color,
					key,
					value,
					$elm$core$Dict$removeMin(left),
					right);
			} else {
				var _v4 = $elm$core$Dict$moveRedLeft(dict);
				if (_v4.$ === -1) {
					var nColor = _v4.a;
					var nKey = _v4.b;
					var nValue = _v4.c;
					var nLeft = _v4.d;
					var nRight = _v4.e;
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						$elm$core$Dict$removeMin(nLeft),
						nRight);
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			}
		} else {
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				key,
				value,
				$elm$core$Dict$removeMin(left),
				right);
		}
	} else {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	}
};
var $elm$core$Dict$removeHelp = F2(
	function (targetKey, dict) {
		if (dict.$ === -2) {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		} else {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			if (_Utils_cmp(targetKey, key) < 0) {
				if ((left.$ === -1) && (left.a === 1)) {
					var _v4 = left.a;
					var lLeft = left.d;
					if ((lLeft.$ === -1) && (!lLeft.a)) {
						var _v6 = lLeft.a;
						return A5(
							$elm$core$Dict$RBNode_elm_builtin,
							color,
							key,
							value,
							A2($elm$core$Dict$removeHelp, targetKey, left),
							right);
					} else {
						var _v7 = $elm$core$Dict$moveRedLeft(dict);
						if (_v7.$ === -1) {
							var nColor = _v7.a;
							var nKey = _v7.b;
							var nValue = _v7.c;
							var nLeft = _v7.d;
							var nRight = _v7.e;
							return A5(
								$elm$core$Dict$balance,
								nColor,
								nKey,
								nValue,
								A2($elm$core$Dict$removeHelp, targetKey, nLeft),
								nRight);
						} else {
							return $elm$core$Dict$RBEmpty_elm_builtin;
						}
					}
				} else {
					return A5(
						$elm$core$Dict$RBNode_elm_builtin,
						color,
						key,
						value,
						A2($elm$core$Dict$removeHelp, targetKey, left),
						right);
				}
			} else {
				return A2(
					$elm$core$Dict$removeHelpEQGT,
					targetKey,
					A7($elm$core$Dict$removeHelpPrepEQGT, targetKey, dict, color, key, value, left, right));
			}
		}
	});
var $elm$core$Dict$removeHelpEQGT = F2(
	function (targetKey, dict) {
		if (dict.$ === -1) {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			if (_Utils_eq(targetKey, key)) {
				var _v1 = $elm$core$Dict$getMin(right);
				if (_v1.$ === -1) {
					var minKey = _v1.b;
					var minValue = _v1.c;
					return A5(
						$elm$core$Dict$balance,
						color,
						minKey,
						minValue,
						left,
						$elm$core$Dict$removeMin(right));
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			} else {
				return A5(
					$elm$core$Dict$balance,
					color,
					key,
					value,
					left,
					A2($elm$core$Dict$removeHelp, targetKey, right));
			}
		} else {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		}
	});
var $elm$core$Dict$remove = F2(
	function (key, dict) {
		var _v0 = A2($elm$core$Dict$removeHelp, key, dict);
		if ((_v0.$ === -1) && (!_v0.a)) {
			var _v1 = _v0.a;
			var k = _v0.b;
			var v = _v0.c;
			var l = _v0.d;
			var r = _v0.e;
			return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
		} else {
			var x = _v0;
			return x;
		}
	});
var $elm$core$Dict$update = F3(
	function (targetKey, alter, dictionary) {
		var _v0 = alter(
			A2($elm$core$Dict$get, targetKey, dictionary));
		if (!_v0.$) {
			var value = _v0.a;
			return A3($elm$core$Dict$insert, targetKey, value, dictionary);
		} else {
			return A2($elm$core$Dict$remove, targetKey, dictionary);
		}
	});
var $elm$core$Basics$composeR = F3(
	function (f, g, x) {
		return g(
			f(x));
	});
var $elm$http$Http$expectStringResponse = F2(
	function (toMsg, toResult) {
		return A3(
			_Http_expect,
			'',
			$elm$core$Basics$identity,
			A2($elm$core$Basics$composeR, toResult, toMsg));
	});
var $elm$http$Http$BadBody = function (a) {
	return {$: 4, a: a};
};
var $elm$http$Http$BadStatus = function (a) {
	return {$: 3, a: a};
};
var $elm$http$Http$BadUrl = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$NetworkError = {$: 2};
var $elm$http$Http$Timeout = {$: 1};
var $elm$core$Result$mapError = F2(
	function (f, result) {
		if (!result.$) {
			var v = result.a;
			return $elm$core$Result$Ok(v);
		} else {
			var e = result.a;
			return $elm$core$Result$Err(
				f(e));
		}
	});
var $elm$http$Http$resolve = F2(
	function (toResult, response) {
		switch (response.$) {
			case 0:
				var url = response.a;
				return $elm$core$Result$Err(
					$elm$http$Http$BadUrl(url));
			case 1:
				return $elm$core$Result$Err($elm$http$Http$Timeout);
			case 2:
				return $elm$core$Result$Err($elm$http$Http$NetworkError);
			case 3:
				var metadata = response.a;
				return $elm$core$Result$Err(
					$elm$http$Http$BadStatus(metadata.cn));
			default:
				var body = response.b;
				return A2(
					$elm$core$Result$mapError,
					$elm$http$Http$BadBody,
					toResult(body));
		}
	});
var $elm$http$Http$expectString = function (toMsg) {
	return A2(
		$elm$http$Http$expectStringResponse,
		toMsg,
		$elm$http$Http$resolve($elm$core$Result$Ok));
};
var $elm$core$Maybe$andThen = F2(
	function (callback, maybeValue) {
		if (!maybeValue.$) {
			var value = maybeValue.a;
			return callback(value);
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $elm$core$List$maybeCons = F3(
	function (f, mx, xs) {
		var _v0 = f(mx);
		if (!_v0.$) {
			var x = _v0.a;
			return A2($elm$core$List$cons, x, xs);
		} else {
			return xs;
		}
	});
var $elm$core$List$filterMap = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$foldr,
			$elm$core$List$maybeCons(f),
			_List_Nil,
			xs);
	});
var $elm$core$List$head = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(x);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$url$Url$percentDecode = _Url_percentDecode;
var $elm$core$Maybe$withDefault = F2(
	function (_default, maybe) {
		if (!maybe.$) {
			var value = maybe.a;
			return value;
		} else {
			return _default;
		}
	});
var $author$project$Main$extractQueryParam = F2(
	function (key, url) {
		return A2(
			$elm$core$Maybe$andThen,
			function (query) {
				return $elm$core$List$head(
					A2(
						$elm$core$List$filterMap,
						function (param) {
							var _v0 = A2($elm$core$String$split, '=', param);
							if ((_v0.b && _v0.b.b) && (!_v0.b.b.b)) {
								var k = _v0.a;
								var _v1 = _v0.b;
								var v = _v1.a;
								return _Utils_eq(k, key) ? $elm$core$Maybe$Just(
									A2(
										$elm$core$Maybe$withDefault,
										v,
										$elm$url$Url$percentDecode(v))) : $elm$core$Maybe$Nothing;
							} else {
								return $elm$core$Maybe$Nothing;
							}
						},
						A2($elm$core$String$split, '&', query)));
			},
			url.ch);
	});
var $elm$http$Http$emptyBody = _Http_emptyBody;
var $elm$http$Http$Request = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$State = F2(
	function (reqs, subs) {
		return {by: reqs, bH: subs};
	});
var $elm$http$Http$init = $elm$core$Task$succeed(
	A2($elm$http$Http$State, $elm$core$Dict$empty, _List_Nil));
var $elm$core$Process$kill = _Scheduler_kill;
var $elm$core$Process$spawn = _Scheduler_spawn;
var $elm$http$Http$updateReqs = F3(
	function (router, cmds, reqs) {
		updateReqs:
		while (true) {
			if (!cmds.b) {
				return $elm$core$Task$succeed(reqs);
			} else {
				var cmd = cmds.a;
				var otherCmds = cmds.b;
				if (!cmd.$) {
					var tracker = cmd.a;
					var _v2 = A2($elm$core$Dict$get, tracker, reqs);
					if (_v2.$ === 1) {
						var $temp$router = router,
							$temp$cmds = otherCmds,
							$temp$reqs = reqs;
						router = $temp$router;
						cmds = $temp$cmds;
						reqs = $temp$reqs;
						continue updateReqs;
					} else {
						var pid = _v2.a;
						return A2(
							$elm$core$Task$andThen,
							function (_v3) {
								return A3(
									$elm$http$Http$updateReqs,
									router,
									otherCmds,
									A2($elm$core$Dict$remove, tracker, reqs));
							},
							$elm$core$Process$kill(pid));
					}
				} else {
					var req = cmd.a;
					return A2(
						$elm$core$Task$andThen,
						function (pid) {
							var _v4 = req.bL;
							if (_v4.$ === 1) {
								return A3($elm$http$Http$updateReqs, router, otherCmds, reqs);
							} else {
								var tracker = _v4.a;
								return A3(
									$elm$http$Http$updateReqs,
									router,
									otherCmds,
									A3($elm$core$Dict$insert, tracker, pid, reqs));
							}
						},
						$elm$core$Process$spawn(
							A3(
								_Http_toTask,
								router,
								$elm$core$Platform$sendToApp(router),
								req)));
				}
			}
		}
	});
var $elm$http$Http$onEffects = F4(
	function (router, cmds, subs, state) {
		return A2(
			$elm$core$Task$andThen,
			function (reqs) {
				return $elm$core$Task$succeed(
					A2($elm$http$Http$State, reqs, subs));
			},
			A3($elm$http$Http$updateReqs, router, cmds, state.by));
	});
var $elm$http$Http$maybeSend = F4(
	function (router, desiredTracker, progress, _v0) {
		var actualTracker = _v0.a;
		var toMsg = _v0.b;
		return _Utils_eq(desiredTracker, actualTracker) ? $elm$core$Maybe$Just(
			A2(
				$elm$core$Platform$sendToApp,
				router,
				toMsg(progress))) : $elm$core$Maybe$Nothing;
	});
var $elm$http$Http$onSelfMsg = F3(
	function (router, _v0, state) {
		var tracker = _v0.a;
		var progress = _v0.b;
		return A2(
			$elm$core$Task$andThen,
			function (_v1) {
				return $elm$core$Task$succeed(state);
			},
			$elm$core$Task$sequence(
				A2(
					$elm$core$List$filterMap,
					A3($elm$http$Http$maybeSend, router, tracker, progress),
					state.bH)));
	});
var $elm$http$Http$Cancel = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$cmdMap = F2(
	function (func, cmd) {
		if (!cmd.$) {
			var tracker = cmd.a;
			return $elm$http$Http$Cancel(tracker);
		} else {
			var r = cmd.a;
			return $elm$http$Http$Request(
				{
					bS: r.bS,
					bV: r.bV,
					a9: A2(_Http_mapExpect, func, r.a9),
					bb: r.bb,
					b8: r.b8,
					cr: r.cr,
					bL: r.bL,
					bN: r.bN
				});
		}
	});
var $elm$http$Http$MySub = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$http$Http$subMap = F2(
	function (func, _v0) {
		var tracker = _v0.a;
		var toMsg = _v0.b;
		return A2(
			$elm$http$Http$MySub,
			tracker,
			A2($elm$core$Basics$composeR, toMsg, func));
	});
_Platform_effectManagers['Http'] = _Platform_createManager($elm$http$Http$init, $elm$http$Http$onEffects, $elm$http$Http$onSelfMsg, $elm$http$Http$cmdMap, $elm$http$Http$subMap);
var $elm$http$Http$command = _Platform_leaf('Http');
var $elm$http$Http$subscription = _Platform_leaf('Http');
var $elm$http$Http$request = function (r) {
	return $elm$http$Http$command(
		$elm$http$Http$Request(
			{bS: false, bV: r.bV, a9: r.a9, bb: r.bb, b8: r.b8, cr: r.cr, bL: r.bL, bN: r.bN}));
};
var $elm$http$Http$get = function (r) {
	return $elm$http$Http$request(
		{bV: $elm$http$Http$emptyBody, a9: r.a9, bb: _List_Nil, b8: 'GET', cr: $elm$core$Maybe$Nothing, bL: $elm$core$Maybe$Nothing, bN: r.bN});
};
var $elm$json$Json$Encode$string = _Json_wrap;
var $author$project$Main$logError = _Platform_outgoingPort('logError', $elm$json$Json$Encode$string);
var $elm$core$Platform$Cmd$batch = _Platform_batch;
var $elm$core$Platform$Cmd$none = $elm$core$Platform$Cmd$batch(_List_Nil);
var $author$project$GpxApi$Track = F3(
	function (trackpoints, waypoints, gainLoss) {
		return {aJ: gainLoss, bM: trackpoints, bP: waypoints};
	});
var $author$project$Main$effectiveWaypoint = function (ew) {
	return {
		a1: A2($elm$core$Maybe$withDefault, ew.x.a1, ew.k.a1),
		az: A2($elm$core$Maybe$withDefault, ew.x.az, ew.k.az),
		aB: ew.x.aB,
		aE: ew.x.aE,
		bn: A2($elm$core$Maybe$withDefault, ew.x.bn, ew.k.bn),
		bo: ew.x.bo
	};
};
var $author$project$Main$effectiveWaypoints = $elm$core$List$filterMap(
	function (ew) {
		return ew.L ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
			$author$project$Main$effectiveWaypoint(ew));
	});
var $elm$json$Json$Encode$float = _Json_wrap;
var $elm$json$Json$Encode$list = F2(
	function (func, entries) {
		return _Json_wrap(
			A3(
				$elm$core$List$foldl,
				_Json_addEntry(func),
				_Json_emptyArray(0),
				entries));
	});
var $elm$json$Json$Encode$object = function (pairs) {
	return _Json_wrap(
		A3(
			$elm$core$List$foldl,
			F2(
				function (_v0, obj) {
					var k = _v0.a;
					var v = _v0.b;
					return A3(_Json_addField, k, v, obj);
				}),
			_Json_emptyObject(0),
			pairs));
};
var $author$project$GpxApi$encodeTrackpoints = $elm$json$Json$Encode$list(
	function (point) {
		return $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'dist',
					$elm$json$Json$Encode$float(point.az)),
					_Utils_Tuple2(
					'ele',
					$elm$json$Json$Encode$float(point.a5)),
					_Utils_Tuple2(
					'lat',
					$elm$json$Json$Encode$float(point.bh)),
					_Utils_Tuple2(
					'lon',
					$elm$json$Json$Encode$float(point.bi)),
					_Utils_Tuple2(
					'gain',
					$elm$json$Json$Encode$float(point.aB)),
					_Utils_Tuple2(
					'loss',
					$elm$json$Json$Encode$float(point.aE))
				]));
	});
var $author$project$GpxApi$encodeWaypoint = function (waypoint) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'dist',
				$elm$json$Json$Encode$float(waypoint.az)),
				_Utils_Tuple2(
				'name',
				$elm$json$Json$Encode$string(waypoint.bn)),
				_Utils_Tuple2(
				'categories',
				A2($elm$json$Json$Encode$list, $elm$json$Json$Encode$string, waypoint.a1)),
				_Utils_Tuple2(
				'gain',
				$elm$json$Json$Encode$float(waypoint.aB)),
				_Utils_Tuple2(
				'loss',
				$elm$json$Json$Encode$float(waypoint.aE)),
				_Utils_Tuple2(
				'offRoute',
				$elm$json$Json$Encode$float(waypoint.bo))
			]));
};
var $elm$core$Tuple$second = function (_v0) {
	var y = _v0.b;
	return y;
};
var $author$project$GpxApi$encodeTrack = function (track) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'track',
				$author$project$GpxApi$encodeTrackpoints(track.bM)),
				_Utils_Tuple2(
				'waypoints',
				A2($elm$json$Json$Encode$list, $author$project$GpxApi$encodeWaypoint, track.bP)),
				_Utils_Tuple2(
				'gain',
				$elm$json$Json$Encode$float(track.aJ.a)),
				_Utils_Tuple2(
				'loss',
				$elm$json$Json$Encode$float(track.aJ.b))
			]));
};
var $elm$core$List$any = F2(
	function (isOkay, list) {
		any:
		while (true) {
			if (!list.b) {
				return false;
			} else {
				var x = list.a;
				var xs = list.b;
				if (isOkay(x)) {
					return true;
				} else {
					var $temp$isOkay = isOkay,
						$temp$list = xs;
					isOkay = $temp$isOkay;
					list = $temp$list;
					continue any;
				}
			}
		}
	});
var $elm$core$Basics$composeL = F3(
	function (g, f, x) {
		return g(
			f(x));
	});
var $elm$core$Basics$not = _Basics_not;
var $elm$core$List$all = F2(
	function (isOkay, list) {
		return !A2(
			$elm$core$List$any,
			A2($elm$core$Basics$composeL, $elm$core$Basics$not, isOkay),
			list);
	});
var $elm$core$List$filter = F2(
	function (isGood, list) {
		return A3(
			$elm$core$List$foldr,
			F2(
				function (x, xs) {
					return isGood(x) ? A2($elm$core$List$cons, x, xs) : xs;
				}),
			_List_Nil,
			list);
	});
var $author$project$Main$filterWaypoints = function (filters) {
	return $elm$core$List$filter(
		function (waypoint) {
			return A2(
				$elm$core$List$all,
				function (filter) {
					return filter(waypoint);
				},
				filters);
		});
};
var $elm$core$List$drop = F2(
	function (n, list) {
		drop:
		while (true) {
			if (n <= 0) {
				return list;
			} else {
				if (!list.b) {
					return list;
				} else {
					var x = list.a;
					var xs = list.b;
					var $temp$n = n - 1,
						$temp$list = xs;
					n = $temp$n;
					list = $temp$list;
					continue drop;
				}
			}
		}
	});
var $elm_community$list_extra$List$Extra$getAt = F2(
	function (idx, xs) {
		return (idx < 0) ? $elm$core$Maybe$Nothing : $elm$core$List$head(
			A2($elm$core$List$drop, idx, xs));
	});
var $elm$json$Json$Encode$int = _Json_wrap;
var $author$project$Main$requestSplitProfile = _Platform_outgoingPort('requestSplitProfile', $elm$json$Json$Encode$string);
var $elm$core$List$sortBy = _List_sortBy;
var $elm$core$List$sort = function (xs) {
	return A2($elm$core$List$sortBy, $elm$core$Basics$identity, xs);
};
var $author$project$Main$unknownCategory = '';
var $author$project$Main$categoryPredicate = F2(
	function (categories, w) {
		var includeCategory = function (cat) {
			return A2(
				$elm$core$Maybe$withDefault,
				true,
				A2($elm$core$Dict$get, cat, categories));
		};
		var _v0 = w.a1;
		if (!_v0.b) {
			return includeCategory($author$project$Main$unknownCategory);
		} else {
			var cats = _v0;
			return A2($elm$core$List$any, includeCategory, cats);
		}
	});
var $elm$core$Basics$ge = _Utils_ge;
var $author$project$Main$offRoutePredicate = F2(
	function (threshold, w) {
		return _Utils_cmp(w.bo, threshold) < 1;
	});
var $author$project$Main$waypointPredicates = function (state) {
	return A2(
		$elm$core$List$filterMap,
		$elm$core$Basics$identity,
		_List_fromArray(
			[
				state.z ? $elm$core$Maybe$Just(
				$author$project$Main$categoryPredicate(state.d)) : $elm$core$Maybe$Nothing,
				state.T ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
				$author$project$Main$offRoutePredicate(state.w)),
				function () {
				var _v0 = _Utils_Tuple2(state.q, state.cg);
				if ((!_v0.a) && (!_v0.b.$)) {
					var _v1 = _v0.a;
					var pos = _v0.b.a;
					var ep = state.a;
					return $elm$core$Maybe$Just(
						function (wp) {
							return (_Utils_cmp(wp.az, pos - ep.C) > -1) && (_Utils_cmp(wp.az, pos + ep.B) < 1);
						});
				} else {
					return $elm$core$Maybe$Nothing;
				}
			}()
			]));
};
var $author$project$Main$requestSplitCmdWasm = function (state) {
	var _v0 = state.b;
	if (_v0.$ === 3) {
		var tracks = _v0.a;
		var filteredWaypoints = A2(
			$author$project$Main$filterWaypoints,
			$author$project$Main$waypointPredicates(state),
			$author$project$Main$effectiveWaypoints(tracks.c.f));
		return $author$project$Main$requestSplitProfile(
			A2(
				$elm$json$Json$Encode$encode,
				0,
				$elm$json$Json$Encode$object(
					_Utils_ap(
						_List_fromArray(
							[
								_Utils_Tuple2(
								'track',
								$author$project$GpxApi$encodeTrack(
									A3($author$project$GpxApi$Track, tracks.c.bM, filteredWaypoints, tracks.c.aJ)))
							]),
						function () {
							var _v1 = state.a.J;
							if (!_v1) {
								return _List_fromArray(
									[
										_Utils_Tuple2(
										'mode',
										$elm$json$Json$Encode$string('equidistant')),
										_Utils_Tuple2(
										'count',
										$elm$json$Json$Encode$int(state.a.aa))
									]);
							} else {
								var distances = $elm$core$List$sort(
									A2(
										$elm$core$List$filterMap,
										function (i) {
											return A2(
												$elm$core$Maybe$andThen,
												function (ew) {
													return ew.L ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
														$author$project$Main$effectiveWaypoint(ew).az);
												},
												A2($elm_community$list_extra$List$Extra$getAt, i, tracks.c.f));
										},
										state.a.l));
								return _List_fromArray(
									[
										_Utils_Tuple2(
										'mode',
										$elm$json$Json$Encode$string('waypoints')),
										_Utils_Tuple2(
										'distances',
										A2($elm$json$Json$Encode$list, $elm$json$Json$Encode$float, distances))
									]);
							}
						}()))));
	} else {
		return $elm$core$Platform$Cmd$none;
	}
};
var $author$project$Main$requestSplitCmd = function (state) {
	var _v0 = state.q;
	if (!_v0) {
		return $elm$core$Platform$Cmd$none;
	} else {
		return $author$project$Main$requestSplitCmdWasm(state);
	}
};
var $author$project$Main$LiveView = 0;
var $author$project$Main$WaypointsMode = 1;
var $author$project$Main$andMap = $elm$json$Json$Decode$map2($elm$core$Basics$apR);
var $elm$json$Json$Decode$bool = _Json_decodeBool;
var $author$project$Zipper$Zipper = F3(
	function (prev, current, next) {
		return {c: current, aF: next, as: prev};
	});
var $elm$json$Json$Decode$field = _Json_decodeField;
var $elm$json$Json$Decode$list = _Json_decodeList;
var $elm$json$Json$Decode$map3 = _Json_map3;
var $author$project$Zipper$decoder = function (elementDecoder) {
	return A4(
		$elm$json$Json$Decode$map3,
		$author$project$Zipper$Zipper,
		A2(
			$elm$json$Json$Decode$field,
			'previous',
			$elm$json$Json$Decode$list(elementDecoder)),
		A2($elm$json$Json$Decode$field, 'current', elementDecoder),
		A2(
			$elm$json$Json$Decode$field,
			'next',
			$elm$json$Json$Decode$list(elementDecoder)));
};
var $elm$core$Dict$fromList = function (assocs) {
	return A3(
		$elm$core$List$foldl,
		F2(
			function (_v0, dict) {
				var key = _v0.a;
				var value = _v0.b;
				return A3($elm$core$Dict$insert, key, value, dict);
			}),
		$elm$core$Dict$empty,
		assocs);
};
var $elm$json$Json$Decode$keyValuePairs = _Json_decodeKeyValuePairs;
var $elm$json$Json$Decode$dict = function (decoder) {
	return A2(
		$elm$json$Json$Decode$map,
		$elm$core$Dict$fromList,
		$elm$json$Json$Decode$keyValuePairs(decoder));
};
var $author$project$Main$EditableTrack = F3(
	function (trackpoints, editableWaypoints, gainLoss) {
		return {f: editableWaypoints, aJ: gainLoss, bM: trackpoints};
	});
var $author$project$GpxApi$TrackPoint = F6(
	function (distance, elevation, lat, lon, gain, loss) {
		return {az: distance, a5: elevation, aB: gain, bh: lat, bi: lon, aE: loss};
	});
var $elm$json$Json$Decode$float = _Json_decodeFloat;
var $elm$json$Json$Decode$map6 = _Json_map6;
var $author$project$GpxApi$decodeTrackpoints = $elm$json$Json$Decode$list(
	A7(
		$elm$json$Json$Decode$map6,
		$author$project$GpxApi$TrackPoint,
		A2($elm$json$Json$Decode$field, 'dist', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'ele', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'lat', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'lon', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'gain', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'loss', $elm$json$Json$Decode$float)));
var $author$project$Main$EditableWaypoint = F3(
	function (original, deleted, overrides) {
		return {L: deleted, x: original, k: overrides};
	});
var $author$project$Main$WaypointOverrides = F3(
	function (name, distance, categories) {
		return {a1: categories, az: distance, bn: name};
	});
var $author$project$GpxApi$Waypoint = F6(
	function (distance, name, categories, gain, loss, offRoute) {
		return {a1: categories, az: distance, aB: gain, aE: loss, bn: name, bo: offRoute};
	});
var $elm$json$Json$Decode$null = _Json_decodeNull;
var $elm$json$Json$Decode$oneOf = _Json_oneOf;
var $author$project$GpxApi$jsonDecodeNullableList = function (elementDecoder) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$elm$json$Json$Decode$list(elementDecoder),
				$elm$json$Json$Decode$null(_List_Nil)
			]));
};
var $elm$json$Json$Decode$map5 = _Json_map5;
var $elm$json$Json$Decode$string = _Json_decodeString;
var $author$project$GpxApi$decodeWaypoint = A3(
	$elm$json$Json$Decode$map2,
	F2(
		function (f, offRoute) {
			return f(offRoute);
		}),
	A6(
		$elm$json$Json$Decode$map5,
		$author$project$GpxApi$Waypoint,
		A2($elm$json$Json$Decode$field, 'dist', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'name', $elm$json$Json$Decode$string),
		A2(
			$elm$json$Json$Decode$field,
			'categories',
			$author$project$GpxApi$jsonDecodeNullableList($elm$json$Json$Decode$string)),
		$elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					A2($elm$json$Json$Decode$field, 'gain', $elm$json$Json$Decode$float),
					$elm$json$Json$Decode$succeed(0)
				])),
		$elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					A2($elm$json$Json$Decode$field, 'loss', $elm$json$Json$Decode$float),
					$elm$json$Json$Decode$succeed(0)
				]))),
	A2($elm$json$Json$Decode$field, 'offRoute', $elm$json$Json$Decode$float));
var $elm$json$Json$Decode$maybe = function (decoder) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, decoder),
				$elm$json$Json$Decode$succeed($elm$core$Maybe$Nothing)
			]));
};
var $author$project$Main$editableWaypointDecoder = A4(
	$elm$json$Json$Decode$map3,
	$author$project$Main$EditableWaypoint,
	A2($elm$json$Json$Decode$field, 'original', $author$project$GpxApi$decodeWaypoint),
	A2($elm$json$Json$Decode$field, 'deleted', $elm$json$Json$Decode$bool),
	A4(
		$elm$json$Json$Decode$map3,
		$author$project$Main$WaypointOverrides,
		$elm$json$Json$Decode$maybe(
			A2($elm$json$Json$Decode$field, 'name', $elm$json$Json$Decode$string)),
		$elm$json$Json$Decode$maybe(
			A2($elm$json$Json$Decode$field, 'distance', $elm$json$Json$Decode$float)),
		$elm$json$Json$Decode$maybe(
			A2(
				$elm$json$Json$Decode$field,
				'categories',
				$elm$json$Json$Decode$list($elm$json$Json$Decode$string)))));
var $elm$core$Tuple$pair = F2(
	function (a, b) {
		return _Utils_Tuple2(a, b);
	});
var $author$project$Main$editableTrackDecoder = A4(
	$elm$json$Json$Decode$map3,
	$author$project$Main$EditableTrack,
	A2($elm$json$Json$Decode$field, 'trackpoints', $author$project$GpxApi$decodeTrackpoints),
	A2(
		$elm$json$Json$Decode$field,
		'editableWaypoints',
		$elm$json$Json$Decode$list($author$project$Main$editableWaypointDecoder)),
	A3(
		$elm$json$Json$Decode$map2,
		$elm$core$Tuple$pair,
		A2($elm$json$Json$Decode$field, 'gain', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'loss', $elm$json$Json$Decode$float)));
var $elm$json$Json$Decode$int = _Json_decodeInt;
var $author$project$Main$Loaded = function (a) {
	return {$: 3, a: a};
};
var $elm$core$Maybe$map = F2(
	function (f, maybe) {
		if (!maybe.$) {
			var value = maybe.a;
			return $elm$core$Maybe$Just(
				f(value));
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $author$project$Main$loadableResourceFromMaybe = A2(
	$elm$core$Basics$composeR,
	$elm$core$Maybe$map($author$project$Main$Loaded),
	$elm$core$Maybe$withDefault($author$project$Main$NotLoaded));
var $author$project$Main$CuesheetTab = 1;
var $author$project$Main$WaypointsTab = 2;
var $author$project$Main$parseTab = function (s) {
	switch (s) {
		case 'elevationProfile':
			return $elm$core$Maybe$Just(0);
		case 'cuesheet':
			return $elm$core$Maybe$Just(1);
		case 'waypoints':
			return $elm$core$Maybe$Just(2);
		default:
			return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Main$FromWaypoint = function (a) {
	return {$: 4, a: a};
};
var $author$project$Main$None = {$: 7};
var $author$project$Main$PercentProgress = {$: 5};
var $author$project$Main$PercentRemaining = {$: 6};
var $author$project$Main$ToFinish = {$: 1};
var $author$project$Main$ToPoint = {$: 2};
var $author$project$Main$ToWaypoint = function (a) {
	return {$: 3, a: a};
};
var $author$project$Main$parseTotalDistanceDisplay = function (v) {
	switch (v) {
		case 'from zero':
			return $elm$core$Maybe$Just($author$project$Main$FromZero);
		case 'to finish':
			return $elm$core$Maybe$Just($author$project$Main$ToFinish);
		case 'to point':
			return $elm$core$Maybe$Just($author$project$Main$ToPoint);
		case '% progress':
			return $elm$core$Maybe$Just($author$project$Main$PercentProgress);
		case '% remaining':
			return $elm$core$Maybe$Just($author$project$Main$PercentRemaining);
		case 'hide':
			return $elm$core$Maybe$Just($author$project$Main$None);
		default:
			if (A2($elm$core$String$startsWith, 'to waypoint', v)) {
				var _v1 = A2($elm$core$String$split, ':', v);
				if ((_v1.b && _v1.b.b) && (!_v1.b.b.b)) {
					var _v2 = _v1.b;
					var idxStr = _v2.a;
					return A2(
						$elm$core$Maybe$map,
						$author$project$Main$ToWaypoint,
						$elm$core$String$toInt(idxStr));
				} else {
					return $elm$core$Maybe$Just(
						$author$project$Main$ToWaypoint(0));
				}
			} else {
				if (A2($elm$core$String$startsWith, 'from waypoint', v)) {
					var _v3 = A2($elm$core$String$split, ':', v);
					if ((_v3.b && _v3.b.b) && (!_v3.b.b.b)) {
						var _v4 = _v3.b;
						var idxStr = _v4.a;
						return A2(
							$elm$core$Maybe$map,
							$author$project$Main$FromWaypoint,
							$elm$core$String$toInt(idxStr));
					} else {
						return $elm$core$Maybe$Just(
							$author$project$Main$FromWaypoint(0));
					}
				} else {
					return $elm$core$Maybe$Nothing;
				}
			}
	}
};
var $author$project$Main$stateDecoder = function () {
	var maybeField = F2(
		function (name, decoder) {
			return $elm$json$Json$Decode$maybe(
				A2($elm$json$Json$Decode$field, name, decoder));
		});
	var defEp = $author$project$Main$defaultElevationProfileOptions;
	var defCs = $author$project$Main$defaultCuesheetOptions;
	return A2(
		$author$project$Main$andMap,
		A2(maybeField, 'showOffRouteWaypoints', $elm$json$Json$Decode$bool),
		A2(
			$author$project$Main$andMap,
			A2(maybeField, 'offRouteThreshold', $elm$json$Json$Decode$float),
			A2(
				$author$project$Main$andMap,
				A2(maybeField, 'showOffRouteDistance', $elm$json$Json$Decode$bool),
				A2(
					$author$project$Main$andMap,
					A2(maybeField, 'showStartFinish', $elm$json$Json$Decode$bool),
					A2(
						$author$project$Main$andMap,
						A2(maybeField, 'distanceDetail', $elm$json$Json$Decode$int),
						A2(
							$author$project$Main$andMap,
							A2(maybeField, 'itemSpacing', $elm$json$Json$Decode$int),
							A2(
								$author$project$Main$andMap,
								A2(maybeField, 'referencePoint', $elm$json$Json$Decode$float),
								A2(
									$author$project$Main$andMap,
									A2(maybeField, 'totalDistanceDisplay', $elm$json$Json$Decode$string),
									A2(
										$author$project$Main$andMap,
										A2(maybeField, 'distanceMarkerSegmentEnds', $elm$json$Json$Decode$bool),
										A2(
											$author$project$Main$andMap,
											A2(maybeField, 'distanceMarkerInterval', $elm$json$Json$Decode$float),
											A2(
												$author$project$Main$andMap,
												A2(maybeField, 'labelHeightGain', $elm$json$Json$Decode$float),
												A2(
													$author$project$Main$andMap,
													A2(maybeField, 'liveLookbehind', $elm$json$Json$Decode$float),
													A2(
														$author$project$Main$andMap,
														A2(maybeField, 'liveLookahead', $elm$json$Json$Decode$float),
														A2(
															$author$project$Main$andMap,
															A2(
																maybeField,
																'splitWaypointIndices',
																$elm$json$Json$Decode$list($elm$json$Json$Decode$int)),
															A2(
																$author$project$Main$andMap,
																A2(maybeField, 'splitEquidistantCount', $elm$json$Json$Decode$int),
																A2(
																	$author$project$Main$andMap,
																	A2(maybeField, 'splitMode', $elm$json$Json$Decode$string),
																	A2(
																		$author$project$Main$andMap,
																		A2(maybeField, 'viewMode', $elm$json$Json$Decode$string),
																		A2(
																			$author$project$Main$andMap,
																			A2(maybeField, 'position', $elm$json$Json$Decode$float),
																			A2(
																				$author$project$Main$andMap,
																				A2(maybeField, 'intensityTau', $elm$json$Json$Decode$float),
																				A2(
																					$author$project$Main$andMap,
																					A2(maybeField, 'showIntensity', $elm$json$Json$Decode$bool),
																					A2(
																						$author$project$Main$andMap,
																						A2(maybeField, 'trackThickness', $elm$json$Json$Decode$float),
																						A2(
																							$author$project$Main$andMap,
																							A2(maybeField, 'trackHeight', $elm$json$Json$Decode$int),
																							A2(
																								$author$project$Main$andMap,
																								A2(maybeField, 'fontSize', $elm$json$Json$Decode$float),
																								A2(
																									$author$project$Main$andMap,
																									A2(
																										maybeField,
																										'filteredCategories',
																										$elm$json$Json$Decode$dict($elm$json$Json$Decode$bool)),
																									A2(
																										$author$project$Main$andMap,
																										A2(maybeField, 'categoryFilterEnabled', $elm$json$Json$Decode$bool),
																										A2(
																											$author$project$Main$andMap,
																											A2(maybeField, 'trackingIntervalSec', $elm$json$Json$Decode$int),
																											A2(
																												$author$project$Main$andMap,
																												A2(maybeField, 'showOptions', $elm$json$Json$Decode$bool),
																												A2(
																													$author$project$Main$andMap,
																													A2(maybeField, 'activeTab', $elm$json$Json$Decode$string),
																													A2(
																														$author$project$Main$andMap,
																														A2(
																															maybeField,
																															'tracks',
																															$author$project$Zipper$decoder($author$project$Main$editableTrackDecoder)),
																														$elm$json$Json$Decode$succeed(
																															function (tracks) {
																																return function (activeTab) {
																																	return function (showOptions) {
																																		return function (trackingIntervalSec) {
																																			return function (categoryFilterEnabled) {
																																				return function (filteredCategories) {
																																					return function (fontSize) {
																																						return function (trackHeight) {
																																							return function (trackThickness) {
																																								return function (showIntensity) {
																																									return function (intensityTau) {
																																										return function (position) {
																																											return function (viewMode) {
																																												return function (splitMode) {
																																													return function (splitEquidistantCount) {
																																														return function (splitWaypointIndices) {
																																															return function (liveLookahead) {
																																																return function (liveLookbehind) {
																																																	return function (labelHeightGain) {
																																																		return function (distanceMarkerInterval) {
																																																			return function (distanceMarkerSegmentEnds) {
																																																				return function (totalDistanceDisplay) {
																																																					return function (referencePoint) {
																																																						return function (itemSpacing) {
																																																							return function (distanceDetail) {
																																																								return function (showStartFinish) {
																																																									return function (showOffRouteDistance) {
																																																										return function (offRouteThreshold) {
																																																											return function (showOffRouteWaypoints) {
																																																												return {
																																																													K: A2(
																																																														$elm$core$Maybe$withDefault,
																																																														$author$project$Main$defaultState.K,
																																																														A2($elm$core$Maybe$andThen, $author$project$Main$parseTab, activeTab)),
																																																													z: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState.z, categoryFilterEnabled),
																																																													e: {
																																																														A: A2($elm$core$Maybe$withDefault, defCs.A, distanceDetail),
																																																														m: A2($elm$core$Maybe$withDefault, defCs.m, itemSpacing),
																																																														t: A2($elm$core$Maybe$withDefault, defCs.t, referencePoint),
																																																														H: A2($elm$core$Maybe$withDefault, defCs.H, showStartFinish),
																																																														h: A2(
																																																															$elm$core$Maybe$withDefault,
																																																															defCs.h,
																																																															A2($elm$core$Maybe$andThen, $author$project$Main$parseTotalDistanceDisplay, totalDistanceDisplay))
																																																													},
																																																													a: {
																																																														J: function () {
																																																															if ((!splitMode.$) && (splitMode.a === 'waypoints')) {
																																																																return 1;
																																																															} else {
																																																																return 0;
																																																															}
																																																														}(),
																																																														M: distanceMarkerInterval,
																																																														N: A2($elm$core$Maybe$withDefault, defEp.N, distanceMarkerSegmentEnds),
																																																														W: A2($elm$core$Maybe$withDefault, defEp.W, fontSize),
																																																														O: A2($elm$core$Maybe$withDefault, defEp.O, intensityTau),
																																																														X: A2($elm$core$Maybe$withDefault, defEp.X, labelHeightGain),
																																																														B: A2($elm$core$Maybe$withDefault, defEp.B, liveLookahead),
																																																														C: A2($elm$core$Maybe$withDefault, defEp.C, liveLookbehind),
																																																														G: A2($elm$core$Maybe$withDefault, defEp.G, showIntensity),
																																																														aa: A2($elm$core$Maybe$withDefault, 1, splitEquidistantCount),
																																																														l: A2($elm$core$Maybe$withDefault, _List_Nil, splitWaypointIndices),
																																																														ac: A2($elm$core$Maybe$withDefault, defEp.ac, trackHeight),
																																																														ad: A2($elm$core$Maybe$withDefault, defEp.ad, trackThickness)
																																																													},
																																																													d: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState.d, filteredCategories),
																																																													ag: $elm$core$Maybe$Nothing,
																																																													Y: $elm$core$Maybe$Nothing,
																																																													Q: $elm$core$Dict$empty,
																																																													w: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState.w, offRouteThreshold),
																																																													cg: position,
																																																													ai: $elm$core$Maybe$Nothing,
																																																													S: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState.S, showOffRouteDistance),
																																																													T: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState.T, showOffRouteWaypoints),
																																																													_: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState._, showOptions),
																																																													I: $elm$core$Maybe$Nothing,
																																																													ab: $elm$core$Maybe$Nothing,
																																																													y: false,
																																																													U: A2($elm$core$Maybe$withDefault, $author$project$Main$defaultState.U, trackingIntervalSec),
																																																													b: $author$project$Main$loadableResourceFromMaybe(tracks),
																																																													q: function () {
																																																														if ((!viewMode.$) && (viewMode.a === 'live')) {
																																																															return 0;
																																																														} else {
																																																															return 1;
																																																														}
																																																													}()
																																																												};
																																																											};
																																																										};
																																																									};
																																																								};
																																																							};
																																																						};
																																																					};
																																																				};
																																																			};
																																																		};
																																																	};
																																																};
																																															};
																																														};
																																													};
																																												};
																																											};
																																										};
																																									};
																																								};
																																							};
																																						};
																																					};
																																				};
																																			};
																																		};
																																	};
																																};
																															}))))))))))))))))))))))))))))));
}();
var $author$project$Main$computeGainLoss = function (tps) {
	var _v0 = $elm$core$List$reverse(tps);
	if (_v0.b) {
		var last = _v0.a;
		if (tps.b) {
			var first = tps.a;
			return _Utils_Tuple2(last.aB - first.aB, last.aE - first.aE);
		} else {
			return _Utils_Tuple2(0, 0);
		}
	} else {
		return _Utils_Tuple2(0, 0);
	}
};
var $elm$core$Basics$min = F2(
	function (x, y) {
		return (_Utils_cmp(x, y) < 0) ? x : y;
	});
var $author$project$Main$computeLiveSplitFromState = function (state) {
	var _v0 = state.b;
	if (_v0.$ === 3) {
		var tracks = _v0.a;
		var tps = tracks.c.bM;
		var maxDist = A2(
			$elm$core$Maybe$withDefault,
			0,
			A2(
				$elm$core$Maybe$map,
				function ($) {
					return $.az;
				},
				$elm$core$List$head(
					$elm$core$List$reverse(tps))));
		var ep = state.a;
		var _v1 = function () {
			var _v2 = state.cg;
			if (!_v2.$) {
				var p = _v2.a;
				return _Utils_Tuple2(
					A2($elm$core$Basics$max, 0, p - ep.C),
					A2($elm$core$Basics$min, maxDist, p + ep.B));
			} else {
				return _Utils_Tuple2(0, maxDist);
			}
		}();
		var rangeStart = _v1.a;
		var rangeEnd = _v1.b;
		var segTps = A2(
			$elm$core$List$filter,
			function (tp) {
				return (_Utils_cmp(tp.az, rangeStart) > -1) && (_Utils_cmp(tp.az, rangeEnd) < 1);
			},
			tps);
		var segWps = A2(
			$elm$core$List$filter,
			function (wp) {
				return (_Utils_cmp(wp.az, rangeStart) > -1) && (_Utils_cmp(wp.az, rangeEnd) < 1);
			},
			A2(
				$author$project$Main$filterWaypoints,
				$author$project$Main$waypointPredicates(state),
				$author$project$Main$effectiveWaypoints(tracks.c.f)));
		var shift = function (record) {
			return _Utils_update(
				record,
				{az: record.az - rangeStart});
		};
		return $elm$core$Maybe$Just(
			{
				bW: _List_fromArray(
					[
						_Utils_Tuple2(rangeStart, rangeEnd)
					]),
				ck: _List_fromArray(
					[
						{
						aJ: $author$project$Main$computeGainLoss(segTps),
						bM: A2($elm$core$List$map, shift, segTps),
						bP: A2($elm$core$List$map, shift, segWps)
					}
					])
			});
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Main$withLiveSplit = function (state) {
	return (!state.q) ? _Utils_update(
		state,
		{
			I: $author$project$Main$computeLiveSplitFromState(state)
		}) : state;
};
var $author$project$Main$init = F3(
	function (maybeState, url, key) {
		var nav = A2($author$project$Main$Navigation, key, url.cf);
		var base = A2($author$project$Main$Model, nav, $author$project$Main$defaultState);
		var _v0 = A2($author$project$Main$extractQueryParam, 'state', url);
		if (!_v0.$) {
			var stateUrl = _v0.a;
			return _Utils_Tuple2(
				base,
				$elm$http$Http$get(
					{
						a9: $elm$http$Http$expectString($author$project$Main$StateUrlFetched),
						bN: stateUrl
					}));
		} else {
			if (maybeState.$ === 1) {
				return _Utils_Tuple2(base, $elm$core$Platform$Cmd$none);
			} else {
				var stateValue = maybeState.a;
				var _v2 = A2($elm$json$Json$Decode$decodeValue, $author$project$Main$stateDecoder, stateValue);
				if (!_v2.$) {
					var decoded = _v2.a;
					var state = $author$project$Main$withLiveSplit(decoded);
					return _Utils_Tuple2(
						A2($author$project$Main$Model, nav, state),
						$author$project$Main$requestSplitCmd(state));
				} else {
					var err = _v2.a;
					var errorMsg = $elm$json$Json$Decode$errorToString(err);
					return _Utils_Tuple2(
						_Utils_update(
							base,
							{
								o: _Utils_update(
									$author$project$Main$defaultState,
									{
										ab: $elm$core$Maybe$Just(errorMsg)
									})
							}),
						$author$project$Main$logError('Failed to decode stored state: ' + errorMsg));
				}
			}
		}
	});
var $author$project$Main$LocationReceived = function (a) {
	return {$: 11, a: a};
};
var $author$project$Main$ProfileWidthChanged = function (a) {
	return {$: 59, a: a};
};
var $author$project$Main$SplitProfileReceived = function (a) {
	return {$: 7, a: a};
};
var $author$project$Main$Tick = function (a) {
	return {$: 15, a: a};
};
var $author$project$Main$WasmResponseReceived = function (a) {
	return {$: 6, a: a};
};
var $elm$core$Platform$Sub$batch = _Platform_batch;
var $elm$time$Time$Every = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$time$Time$State = F2(
	function (taggers, processes) {
		return {bu: processes, bJ: taggers};
	});
var $elm$time$Time$init = $elm$core$Task$succeed(
	A2($elm$time$Time$State, $elm$core$Dict$empty, $elm$core$Dict$empty));
var $elm$time$Time$addMySub = F2(
	function (_v0, state) {
		var interval = _v0.a;
		var tagger = _v0.b;
		var _v1 = A2($elm$core$Dict$get, interval, state);
		if (_v1.$ === 1) {
			return A3(
				$elm$core$Dict$insert,
				interval,
				_List_fromArray(
					[tagger]),
				state);
		} else {
			var taggers = _v1.a;
			return A3(
				$elm$core$Dict$insert,
				interval,
				A2($elm$core$List$cons, tagger, taggers),
				state);
		}
	});
var $elm$core$Dict$foldl = F3(
	function (func, acc, dict) {
		foldl:
		while (true) {
			if (dict.$ === -2) {
				return acc;
			} else {
				var key = dict.b;
				var value = dict.c;
				var left = dict.d;
				var right = dict.e;
				var $temp$func = func,
					$temp$acc = A3(
					func,
					key,
					value,
					A3($elm$core$Dict$foldl, func, acc, left)),
					$temp$dict = right;
				func = $temp$func;
				acc = $temp$acc;
				dict = $temp$dict;
				continue foldl;
			}
		}
	});
var $elm$core$Dict$merge = F6(
	function (leftStep, bothStep, rightStep, leftDict, rightDict, initialResult) {
		var stepState = F3(
			function (rKey, rValue, _v0) {
				stepState:
				while (true) {
					var list = _v0.a;
					var result = _v0.b;
					if (!list.b) {
						return _Utils_Tuple2(
							list,
							A3(rightStep, rKey, rValue, result));
					} else {
						var _v2 = list.a;
						var lKey = _v2.a;
						var lValue = _v2.b;
						var rest = list.b;
						if (_Utils_cmp(lKey, rKey) < 0) {
							var $temp$rKey = rKey,
								$temp$rValue = rValue,
								$temp$_v0 = _Utils_Tuple2(
								rest,
								A3(leftStep, lKey, lValue, result));
							rKey = $temp$rKey;
							rValue = $temp$rValue;
							_v0 = $temp$_v0;
							continue stepState;
						} else {
							if (_Utils_cmp(lKey, rKey) > 0) {
								return _Utils_Tuple2(
									list,
									A3(rightStep, rKey, rValue, result));
							} else {
								return _Utils_Tuple2(
									rest,
									A4(bothStep, lKey, lValue, rValue, result));
							}
						}
					}
				}
			});
		var _v3 = A3(
			$elm$core$Dict$foldl,
			stepState,
			_Utils_Tuple2(
				$elm$core$Dict$toList(leftDict),
				initialResult),
			rightDict);
		var leftovers = _v3.a;
		var intermediateResult = _v3.b;
		return A3(
			$elm$core$List$foldl,
			F2(
				function (_v4, result) {
					var k = _v4.a;
					var v = _v4.b;
					return A3(leftStep, k, v, result);
				}),
			intermediateResult,
			leftovers);
	});
var $elm$time$Time$Name = function (a) {
	return {$: 0, a: a};
};
var $elm$time$Time$Offset = function (a) {
	return {$: 1, a: a};
};
var $elm$time$Time$Zone = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$time$Time$customZone = $elm$time$Time$Zone;
var $elm$time$Time$setInterval = _Time_setInterval;
var $elm$time$Time$spawnHelp = F3(
	function (router, intervals, processes) {
		if (!intervals.b) {
			return $elm$core$Task$succeed(processes);
		} else {
			var interval = intervals.a;
			var rest = intervals.b;
			var spawnTimer = $elm$core$Process$spawn(
				A2(
					$elm$time$Time$setInterval,
					interval,
					A2($elm$core$Platform$sendToSelf, router, interval)));
			var spawnRest = function (id) {
				return A3(
					$elm$time$Time$spawnHelp,
					router,
					rest,
					A3($elm$core$Dict$insert, interval, id, processes));
			};
			return A2($elm$core$Task$andThen, spawnRest, spawnTimer);
		}
	});
var $elm$time$Time$onEffects = F3(
	function (router, subs, _v0) {
		var processes = _v0.bu;
		var rightStep = F3(
			function (_v6, id, _v7) {
				var spawns = _v7.a;
				var existing = _v7.b;
				var kills = _v7.c;
				return _Utils_Tuple3(
					spawns,
					existing,
					A2(
						$elm$core$Task$andThen,
						function (_v5) {
							return kills;
						},
						$elm$core$Process$kill(id)));
			});
		var newTaggers = A3($elm$core$List$foldl, $elm$time$Time$addMySub, $elm$core$Dict$empty, subs);
		var leftStep = F3(
			function (interval, taggers, _v4) {
				var spawns = _v4.a;
				var existing = _v4.b;
				var kills = _v4.c;
				return _Utils_Tuple3(
					A2($elm$core$List$cons, interval, spawns),
					existing,
					kills);
			});
		var bothStep = F4(
			function (interval, taggers, id, _v3) {
				var spawns = _v3.a;
				var existing = _v3.b;
				var kills = _v3.c;
				return _Utils_Tuple3(
					spawns,
					A3($elm$core$Dict$insert, interval, id, existing),
					kills);
			});
		var _v1 = A6(
			$elm$core$Dict$merge,
			leftStep,
			bothStep,
			rightStep,
			newTaggers,
			processes,
			_Utils_Tuple3(
				_List_Nil,
				$elm$core$Dict$empty,
				$elm$core$Task$succeed(0)));
		var spawnList = _v1.a;
		var existingDict = _v1.b;
		var killTask = _v1.c;
		return A2(
			$elm$core$Task$andThen,
			function (newProcesses) {
				return $elm$core$Task$succeed(
					A2($elm$time$Time$State, newTaggers, newProcesses));
			},
			A2(
				$elm$core$Task$andThen,
				function (_v2) {
					return A3($elm$time$Time$spawnHelp, router, spawnList, existingDict);
				},
				killTask));
	});
var $elm$time$Time$Posix = $elm$core$Basics$identity;
var $elm$time$Time$millisToPosix = $elm$core$Basics$identity;
var $elm$time$Time$now = _Time_now($elm$time$Time$millisToPosix);
var $elm$time$Time$onSelfMsg = F3(
	function (router, interval, state) {
		var _v0 = A2($elm$core$Dict$get, interval, state.bJ);
		if (_v0.$ === 1) {
			return $elm$core$Task$succeed(state);
		} else {
			var taggers = _v0.a;
			var tellTaggers = function (time) {
				return $elm$core$Task$sequence(
					A2(
						$elm$core$List$map,
						function (tagger) {
							return A2(
								$elm$core$Platform$sendToApp,
								router,
								tagger(time));
						},
						taggers));
			};
			return A2(
				$elm$core$Task$andThen,
				function (_v1) {
					return $elm$core$Task$succeed(state);
				},
				A2($elm$core$Task$andThen, tellTaggers, $elm$time$Time$now));
		}
	});
var $elm$time$Time$subMap = F2(
	function (f, _v0) {
		var interval = _v0.a;
		var tagger = _v0.b;
		return A2(
			$elm$time$Time$Every,
			interval,
			A2($elm$core$Basics$composeL, f, tagger));
	});
_Platform_effectManagers['Time'] = _Platform_createManager($elm$time$Time$init, $elm$time$Time$onEffects, $elm$time$Time$onSelfMsg, 0, $elm$time$Time$subMap);
var $elm$time$Time$subscription = _Platform_leaf('Time');
var $elm$time$Time$every = F2(
	function (interval, tagger) {
		return $elm$time$Time$subscription(
			A2($elm$time$Time$Every, interval, tagger));
	});
var $elm$core$Platform$Sub$none = $elm$core$Platform$Sub$batch(_List_Nil);
var $author$project$Main$profileWidthChanged = _Platform_incomingPort('profileWidthChanged', $elm$json$Json$Decode$int);
var $author$project$Main$receiveElevationProfileData = _Platform_incomingPort('receiveElevationProfileData', $elm$json$Json$Decode$string);
var $elm$json$Json$Decode$value = _Json_decodeValue;
var $author$project$Main$receiveLocation = _Platform_incomingPort('receiveLocation', $elm$json$Json$Decode$value);
var $author$project$Main$receiveSplitProfile = _Platform_incomingPort('receiveSplitProfile', $elm$json$Json$Decode$string);
var $author$project$Main$subscriptions = function (_v0) {
	var state = _v0.o;
	return $elm$core$Platform$Sub$batch(
		_List_fromArray(
			[
				$author$project$Main$receiveLocation($author$project$Main$LocationReceived),
				state.y ? A2($elm$time$Time$every, state.U * 1000, $author$project$Main$Tick) : $elm$core$Platform$Sub$none,
				$author$project$Main$receiveElevationProfileData($author$project$Main$WasmResponseReceived),
				$author$project$Main$receiveSplitProfile($author$project$Main$SplitProfileReceived),
				$author$project$Main$profileWidthChanged($author$project$Main$ProfileWidthChanged)
			]));
};
var $author$project$Main$Error = function (a) {
	return {$: 2, a: a};
};
var $author$project$Main$FileUploaded = function (a) {
	return {$: 4, a: a};
};
var $author$project$Main$GPXStringed = function (a) {
	return {$: 5, a: a};
};
var $author$project$Location$LatLon = F2(
	function (lat, lon) {
		return {bh: lat, bi: lon};
	});
var $author$project$Main$Loading = {$: 1};
var $author$project$Location$LocationState = F4(
	function (position, accuracy, matchedDistance, offRouteDistance) {
		return {a_: accuracy, b6: matchedDistance, cb: offRouteDistance, cg: position};
	});
var $author$project$Location$PositionUnavailable = 1;
var $author$project$Main$StateFileRead = function (a) {
	return {$: 56, a: a};
};
var $author$project$Main$StateFileSelected = function (a) {
	return {$: 55, a: a};
};
var $author$project$Main$calculateElevationProfileData = _Platform_outgoingPort('calculateElevationProfileData', $elm$json$Json$Encode$string);
var $elm$core$List$append = F2(
	function (xs, ys) {
		if (!ys.b) {
			return xs;
		} else {
			return A3($elm$core$List$foldr, $elm$core$List$cons, ys, xs);
		}
	});
var $elm$core$List$concat = function (lists) {
	return A3($elm$core$List$foldr, $elm$core$List$append, _List_Nil, lists);
};
var $elm$core$List$concatMap = F2(
	function (f, list) {
		return $elm$core$List$concat(
			A2($elm$core$List$map, f, list));
	});
var $elm_community$list_extra$List$Extra$last = function (items) {
	last:
	while (true) {
		if (!items.b) {
			return $elm$core$Maybe$Nothing;
		} else {
			if (!items.b.b) {
				var x = items.a;
				return $elm$core$Maybe$Just(x);
			} else {
				var rest = items.b;
				var $temp$items = rest;
				items = $temp$items;
				continue last;
			}
		}
	}
};
var $author$project$Main$correctWaypointSelection = F2(
	function (display, indexed) {
		switch (display.$) {
			case 3:
				var idx = display.a;
				if (A2(
					$elm$core$List$any,
					function (_v1) {
						var i = _v1.a;
						return _Utils_eq(i, idx);
					},
					indexed)) {
					return display;
				} else {
					var _v2 = $elm_community$list_extra$List$Extra$last(indexed);
					if (!_v2.$) {
						var _v3 = _v2.a;
						var lastIdx = _v3.a;
						return $author$project$Main$ToWaypoint(lastIdx);
					} else {
						return display;
					}
				}
			case 4:
				var idx = display.a;
				if (A2(
					$elm$core$List$any,
					function (_v4) {
						var i = _v4.a;
						return _Utils_eq(i, idx);
					},
					indexed)) {
					return display;
				} else {
					var _v5 = $elm$core$List$head(indexed);
					if (!_v5.$) {
						var _v6 = _v5.a;
						var firstIdx = _v6.a;
						return $author$project$Main$FromWaypoint(firstIdx);
					} else {
						return display;
					}
				}
			default:
				return display;
		}
	});
var $elm$core$List$member = F2(
	function (x, xs) {
		return A2(
			$elm$core$List$any,
			function (a) {
				return _Utils_eq(a, x);
			},
			xs);
	});
var $author$project$Main$indexedFilteredWaypoints = F2(
	function (allWaypoints, filtered) {
		return A2(
			$elm$core$List$filter,
			function (_v0) {
				var wp = _v0.b;
				return A2($elm$core$List$member, wp, filtered);
			},
			A2($elm$core$List$indexedMap, $elm$core$Tuple$pair, allWaypoints));
	});
var $author$project$Main$maybeFromloadableResource = function (resource) {
	if (resource.$ === 3) {
		var a = resource.a;
		return $elm$core$Maybe$Just(a);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Main$correctWaypointSelectionInState = function (s) {
	var _v0 = $author$project$Main$maybeFromloadableResource(s.b);
	if (_v0.$ === 1) {
		return s;
	} else {
		var tracks = _v0.a;
		var cs = s.e;
		var allWaypoints = $author$project$Main$effectiveWaypoints(tracks.c.f);
		var filtered = A2(
			$author$project$Main$filterWaypoints,
			$author$project$Main$waypointPredicates(s),
			allWaypoints);
		var indexed = A2($author$project$Main$indexedFilteredWaypoints, allWaypoints, filtered);
		var corrected = A2($author$project$Main$correctWaypointSelection, cs.h, indexed);
		return _Utils_update(
			s,
			{
				e: _Utils_update(
					cs,
					{h: corrected})
			});
	}
};
var $author$project$GpxApi$decodeTrack = A4(
	$elm$json$Json$Decode$map3,
	$author$project$GpxApi$Track,
	A2($elm$json$Json$Decode$field, 'track', $author$project$GpxApi$decodeTrackpoints),
	A2(
		$elm$json$Json$Decode$field,
		'waypoints',
		$elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					$elm$json$Json$Decode$list($author$project$GpxApi$decodeWaypoint),
					$elm$json$Json$Decode$null(_List_Nil)
				]))),
	A3(
		$elm$json$Json$Decode$map2,
		$elm$core$Tuple$pair,
		A2($elm$json$Json$Decode$field, 'gain', $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$field, 'loss', $elm$json$Json$Decode$float)));
var $author$project$GpxApi$decodeElevationProfileDataResponse = $elm$json$Json$Decode$list($author$project$GpxApi$decodeTrack);
var $author$project$Location$GeoTimeout = 2;
var $author$project$Location$PermissionDenied = 0;
var $author$project$Location$decodeLocationResult = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			A2(
			$elm$json$Json$Decode$map,
			function (code) {
				return $elm$core$Result$Err(
					function () {
						switch (code) {
							case 'permission_denied':
								return 0;
							case 'timeout':
								return 2;
							default:
								return 1;
						}
					}());
			},
			A2($elm$json$Json$Decode$field, 'error', $elm$json$Json$Decode$string)),
			A4(
			$elm$json$Json$Decode$map3,
			F3(
				function (lat, lon, acc) {
					return $elm$core$Result$Ok(
						{a_: acc, bh: lat, bi: lon});
				}),
			A2($elm$json$Json$Decode$field, 'lat', $elm$json$Json$Decode$float),
			A2($elm$json$Json$Decode$field, 'lon', $elm$json$Json$Decode$float),
			A2($elm$json$Json$Decode$field, 'accuracy', $elm$json$Json$Decode$float))
		]));
var $author$project$GpxApi$decodeResult = function (decoder) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2(
				$elm$json$Json$Decode$map,
				$elm$core$Result$Err,
				A2($elm$json$Json$Decode$field, 'error', $elm$json$Json$Decode$string)),
				A2($elm$json$Json$Decode$map, $elm$core$Result$Ok, decoder)
			]));
};
var $author$project$GpxApi$SplitResult = F2(
	function (segments, boundaries) {
		return {bW: boundaries, ck: segments};
	});
var $elm$json$Json$Decode$index = _Json_decodeIndex;
var $author$project$GpxApi$decodeBoundaries = $elm$json$Json$Decode$list(
	A3(
		$elm$json$Json$Decode$map2,
		$elm$core$Tuple$pair,
		A2($elm$json$Json$Decode$index, 0, $elm$json$Json$Decode$float),
		A2($elm$json$Json$Decode$index, 1, $elm$json$Json$Decode$float)));
var $author$project$GpxApi$decodeSplitResult = A3(
	$elm$json$Json$Decode$map2,
	$author$project$GpxApi$SplitResult,
	A2(
		$elm$json$Json$Decode$field,
		'segments',
		$elm$json$Json$Decode$list($author$project$GpxApi$decodeTrack)),
	A2($elm$json$Json$Decode$field, 'boundaries', $author$project$GpxApi$decodeBoundaries));
var $elm$json$Json$Decode$decodeString = _Json_runOnString;
var $author$project$Main$downloadState = _Platform_outgoingPort('downloadState', $elm$json$Json$Encode$string);
var $author$project$Main$emptyOverrides = A3($author$project$Main$WaypointOverrides, $elm$core$Maybe$Nothing, $elm$core$Maybe$Nothing, $elm$core$Maybe$Nothing);
var $author$project$Main$editableTrackFromGpxTrack = function (track) {
	return {
		f: A2(
			$elm$core$List$map,
			function (w) {
				return A3($author$project$Main$EditableWaypoint, w, false, $author$project$Main$emptyOverrides);
			},
			track.bP),
		aJ: track.aJ,
		bM: track.bM
	};
};
var $elm$json$Json$Encode$bool = _Json_wrap;
var $elm$json$Json$Encode$dict = F3(
	function (toKey, toValue, dictionary) {
		return _Json_wrap(
			A3(
				$elm$core$Dict$foldl,
				F3(
					function (key, value, obj) {
						return A3(
							_Json_addField,
							toKey(key),
							toValue(value),
							obj);
					}),
				_Json_emptyObject(0),
				dictionary));
	});
var $author$project$Zipper$encode = F2(
	function (encodeElement, zipper) {
		return $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'previous',
					A2($elm$json$Json$Encode$list, encodeElement, zipper.as)),
					_Utils_Tuple2(
					'current',
					encodeElement(zipper.c)),
					_Utils_Tuple2(
					'next',
					A2($elm$json$Json$Encode$list, encodeElement, zipper.aF))
				]));
	});
var $author$project$Main$encodeEditableWaypoint = function (ew) {
	return $elm$json$Json$Encode$object(
		A2(
			$elm$core$List$filterMap,
			$elm$core$Basics$identity,
			_List_fromArray(
				[
					$elm$core$Maybe$Just(
					_Utils_Tuple2(
						'original',
						$author$project$GpxApi$encodeWaypoint(ew.x))),
					$elm$core$Maybe$Just(
					_Utils_Tuple2(
						'deleted',
						$elm$json$Json$Encode$bool(ew.L))),
					A2(
					$elm$core$Maybe$map,
					function (n) {
						return _Utils_Tuple2(
							'name',
							$elm$json$Json$Encode$string(n));
					},
					ew.k.bn),
					A2(
					$elm$core$Maybe$map,
					function (d) {
						return _Utils_Tuple2(
							'distance',
							$elm$json$Json$Encode$float(d));
					},
					ew.k.az),
					A2(
					$elm$core$Maybe$map,
					function (cats) {
						return _Utils_Tuple2(
							'categories',
							A2($elm$json$Json$Encode$list, $elm$json$Json$Encode$string, cats));
					},
					ew.k.a1)
				])));
};
var $author$project$Main$encodeEditableTrack = function (track) {
	return $elm$json$Json$Encode$object(
		_List_fromArray(
			[
				_Utils_Tuple2(
				'trackpoints',
				$author$project$GpxApi$encodeTrackpoints(track.bM)),
				_Utils_Tuple2(
				'editableWaypoints',
				A2($elm$json$Json$Encode$list, $author$project$Main$encodeEditableWaypoint, track.f)),
				_Utils_Tuple2(
				'gain',
				$elm$json$Json$Encode$float(track.aJ.a)),
				_Utils_Tuple2(
				'loss',
				$elm$json$Json$Encode$float(track.aJ.b))
			]));
};
var $author$project$Main$formatTab = function (tab) {
	switch (tab) {
		case 0:
			return 'elevationProfile';
		case 1:
			return 'cuesheet';
		default:
			return 'waypoints';
	}
};
var $author$project$Main$formatTotalDistanceDisplay = function (v) {
	switch (v.$) {
		case 0:
			return 'from zero';
		case 1:
			return 'to finish';
		case 2:
			return 'to point';
		case 3:
			var idx = v.a;
			return 'to waypoint:' + $elm$core$String$fromInt(idx);
		case 4:
			var idx = v.a;
			return 'from waypoint:' + $elm$core$String$fromInt(idx);
		case 5:
			return '% progress';
		case 6:
			return '% remaining';
		default:
			return 'hide';
	}
};
var $author$project$Main$encodeSavedState = function (state) {
	var ep = state.a;
	var cs = state.e;
	return A2(
		$elm$json$Json$Encode$encode,
		0,
		$elm$json$Json$Encode$object(
			A2(
				$elm$core$List$filterMap,
				$elm$core$Basics$identity,
				_List_fromArray(
					[
						A2(
						$elm$core$Maybe$map,
						function (tracks) {
							return _Utils_Tuple2(
								'tracks',
								A2($author$project$Zipper$encode, $author$project$Main$encodeEditableTrack, tracks));
						},
						$author$project$Main$maybeFromloadableResource(state.b)),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'activeTab',
							$elm$json$Json$Encode$string(
								$author$project$Main$formatTab(state.K)))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'showOptions',
							$elm$json$Json$Encode$bool(state._))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'trackingIntervalSec',
							$elm$json$Json$Encode$int(state.U))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'categoryFilterEnabled',
							$elm$json$Json$Encode$bool(state.z))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'filteredCategories',
							A3($elm$json$Json$Encode$dict, $elm$core$Basics$identity, $elm$json$Json$Encode$bool, state.d))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'fontSize',
							$elm$json$Json$Encode$float(ep.W))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'trackHeight',
							$elm$json$Json$Encode$int(ep.ac))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'trackThickness',
							$elm$json$Json$Encode$float(ep.ad))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'showIntensity',
							$elm$json$Json$Encode$bool(ep.G))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'intensityTau',
							$elm$json$Json$Encode$float(ep.O))),
						A2(
						$elm$core$Maybe$map,
						function (pos) {
							return _Utils_Tuple2(
								'position',
								$elm$json$Json$Encode$float(pos));
						},
						state.cg),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'viewMode',
							$elm$json$Json$Encode$string(
								function () {
									var _v0 = state.q;
									if (!_v0) {
										return 'live';
									} else {
										return 'static';
									}
								}()))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'splitMode',
							$elm$json$Json$Encode$string(
								function () {
									var _v1 = ep.J;
									if (!_v1) {
										return 'equidistant';
									} else {
										return 'waypoints';
									}
								}()))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'splitEquidistantCount',
							$elm$json$Json$Encode$int(ep.aa))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'splitWaypointIndices',
							A2($elm$json$Json$Encode$list, $elm$json$Json$Encode$int, ep.l))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'liveLookahead',
							$elm$json$Json$Encode$float(ep.B))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'liveLookbehind',
							$elm$json$Json$Encode$float(ep.C))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'labelHeightGain',
							$elm$json$Json$Encode$float(ep.X))),
						A2(
						$elm$core$Maybe$map,
						function (m) {
							return _Utils_Tuple2(
								'distanceMarkerInterval',
								$elm$json$Json$Encode$float(m));
						},
						ep.M),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'distanceMarkerSegmentEnds',
							$elm$json$Json$Encode$bool(ep.N))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'totalDistanceDisplay',
							$elm$json$Json$Encode$string(
								$author$project$Main$formatTotalDistanceDisplay(cs.h)))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'referencePoint',
							$elm$json$Json$Encode$float(cs.t))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'itemSpacing',
							$elm$json$Json$Encode$int(cs.m))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'distanceDetail',
							$elm$json$Json$Encode$int(cs.A))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'showStartFinish',
							$elm$json$Json$Encode$bool(cs.H))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'offRouteThreshold',
							$elm$json$Json$Encode$float(state.w))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'showOffRouteWaypoints',
							$elm$json$Json$Encode$bool(state.T))),
						$elm$core$Maybe$Just(
						_Utils_Tuple2(
							'showOffRouteDistance',
							$elm$json$Json$Encode$bool(state.S)))
					]))));
};
var $elm$file$File$Select$file = F2(
	function (mimes, toMsg) {
		return A2(
			$elm$core$Task$perform,
			toMsg,
			_File_uploadOne(mimes));
	});
var $elm$core$Basics$asin = _Basics_asin;
var $elm$core$Basics$cos = _Basics_cos;
var $elm$core$Basics$pi = _Basics_pi;
var $elm$core$Basics$sin = _Basics_sin;
var $elm$core$Basics$sqrt = _Basics_sqrt;
var $author$project$Location$haversineDistance = F2(
	function (a, b) {
		var toRad = function (deg) {
			return (deg * $elm$core$Basics$pi) / 180;
		};
		var r = 6371000;
		var dLon = toRad(b.bi - a.bi);
		var sinDLon = $elm$core$Basics$sin(dLon / 2);
		var dLat = toRad(b.bh - a.bh);
		var sinDLat = $elm$core$Basics$sin(dLat / 2);
		var h = (sinDLat * sinDLat) + ((($elm$core$Basics$cos(
			toRad(a.bh)) * $elm$core$Basics$cos(
			toRad(b.bh))) * sinDLon) * sinDLon);
		return (2 * r) * $elm$core$Basics$asin(
			$elm$core$Basics$sqrt(h));
	});
var $author$project$Location$findNearestTrackPoint = F2(
	function (pos, trackpoints) {
		return A2(
			$elm$core$Maybe$map,
			$elm$core$Tuple$second,
			$elm$core$List$head(
				A2(
					$elm$core$List$sortBy,
					$elm$core$Tuple$first,
					A2(
						$elm$core$List$map,
						function (tp) {
							return _Utils_Tuple2(
								A2(
									$author$project$Location$haversineDistance,
									pos,
									A2($author$project$Location$LatLon, tp.bh, tp.bi)),
								tp);
						},
						trackpoints))));
	});
var $author$project$Zipper$fromList = function (elements) {
	if (elements.b) {
		var first = elements.a;
		var rest = elements.b;
		return $elm$core$Maybe$Just(
			A3($author$project$Zipper$Zipper, _List_Nil, first, rest));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Main$indexedEffectiveWaypoints = A2(
	$elm$core$Basics$composeR,
	$elm$core$List$indexedMap($elm$core$Tuple$pair),
	$elm$core$List$filterMap(
		function (_v0) {
			var i = _v0.a;
			var ew = _v0.b;
			return ew.L ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
				_Utils_Tuple2(
					i,
					$author$project$Main$effectiveWaypoint(ew)));
		}));
var $elm$core$List$isEmpty = function (xs) {
	if (!xs.b) {
		return true;
	} else {
		return false;
	}
};
var $author$project$Main$initialFilteredCategories = A2(
	$elm$core$Basics$composeR,
	A2(
		$elm$core$List$foldl,
		F2(
			function (w, _v0) {
				var acc = _v0.a;
				var includeUnknown = _v0.b;
				return $elm$core$List$isEmpty(w.a1) ? _Utils_Tuple2(acc, true) : _Utils_Tuple2(
					A3(
						$elm$core$List$foldl,
						F2(
							function (cat, d) {
								return A3($elm$core$Dict$insert, cat, true, d);
							}),
						acc,
						w.a1),
					includeUnknown);
			}),
		_Utils_Tuple2($elm$core$Dict$empty, false)),
	function (_v1) {
		var d = _v1.a;
		var hasUnknown = _v1.b;
		return hasUnknown ? A3($elm$core$Dict$insert, $author$project$Main$unknownCategory, true, d) : d;
	});
var $elm$core$Dict$map = F2(
	function (func, dict) {
		if (dict.$ === -2) {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		} else {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				key,
				A2(func, key, value),
				A2($elm$core$Dict$map, func, left),
				A2($elm$core$Dict$map, func, right));
		}
	});
var $elm$core$Tuple$mapSecond = F2(
	function (func, _v0) {
		var x = _v0.a;
		var y = _v0.b;
		return _Utils_Tuple2(
			x,
			func(y));
	});
var $elm$core$Dict$member = F2(
	function (key, dict) {
		var _v0 = A2($elm$core$Dict$get, key, dict);
		if (!_v0.$) {
			return true;
		} else {
			return false;
		}
	});
var $author$project$Zipper$navigateNext = function (zipper) {
	var _v0 = zipper.aF;
	if (!_v0.b) {
		return zipper;
	} else {
		var first = _v0.a;
		var rest = _v0.b;
		return A3(
			$author$project$Zipper$Zipper,
			A2($elm$core$List$cons, zipper.c, zipper.as),
			first,
			rest);
	}
};
var $author$project$Zipper$navigatePrevious = function (zipper) {
	var _v0 = zipper.as;
	if (!_v0.b) {
		return zipper;
	} else {
		var first = _v0.a;
		var rest = _v0.b;
		return A3(
			$author$project$Zipper$Zipper,
			rest,
			first,
			A2($elm$core$List$cons, zipper.c, zipper.aF));
	}
};
var $elm$core$Basics$neq = _Utils_notEqual;
var $elm$core$List$takeReverse = F3(
	function (n, list, kept) {
		takeReverse:
		while (true) {
			if (n <= 0) {
				return kept;
			} else {
				if (!list.b) {
					return kept;
				} else {
					var x = list.a;
					var xs = list.b;
					var $temp$n = n - 1,
						$temp$list = xs,
						$temp$kept = A2($elm$core$List$cons, x, kept);
					n = $temp$n;
					list = $temp$list;
					kept = $temp$kept;
					continue takeReverse;
				}
			}
		}
	});
var $elm$core$List$takeTailRec = F2(
	function (n, list) {
		return $elm$core$List$reverse(
			A3($elm$core$List$takeReverse, n, list, _List_Nil));
	});
var $elm$core$List$takeFast = F3(
	function (ctr, n, list) {
		if (n <= 0) {
			return _List_Nil;
		} else {
			var _v0 = _Utils_Tuple2(n, list);
			_v0$1:
			while (true) {
				_v0$5:
				while (true) {
					if (!_v0.b.b) {
						return list;
					} else {
						if (_v0.b.b.b) {
							switch (_v0.a) {
								case 1:
									break _v0$1;
								case 2:
									var _v2 = _v0.b;
									var x = _v2.a;
									var _v3 = _v2.b;
									var y = _v3.a;
									return _List_fromArray(
										[x, y]);
								case 3:
									if (_v0.b.b.b.b) {
										var _v4 = _v0.b;
										var x = _v4.a;
										var _v5 = _v4.b;
										var y = _v5.a;
										var _v6 = _v5.b;
										var z = _v6.a;
										return _List_fromArray(
											[x, y, z]);
									} else {
										break _v0$5;
									}
								default:
									if (_v0.b.b.b.b && _v0.b.b.b.b.b) {
										var _v7 = _v0.b;
										var x = _v7.a;
										var _v8 = _v7.b;
										var y = _v8.a;
										var _v9 = _v8.b;
										var z = _v9.a;
										var _v10 = _v9.b;
										var w = _v10.a;
										var tl = _v10.b;
										return (ctr > 1000) ? A2(
											$elm$core$List$cons,
											x,
											A2(
												$elm$core$List$cons,
												y,
												A2(
													$elm$core$List$cons,
													z,
													A2(
														$elm$core$List$cons,
														w,
														A2($elm$core$List$takeTailRec, n - 4, tl))))) : A2(
											$elm$core$List$cons,
											x,
											A2(
												$elm$core$List$cons,
												y,
												A2(
													$elm$core$List$cons,
													z,
													A2(
														$elm$core$List$cons,
														w,
														A3($elm$core$List$takeFast, ctr + 1, n - 4, tl)))));
									} else {
										break _v0$5;
									}
							}
						} else {
							if (_v0.a === 1) {
								break _v0$1;
							} else {
								break _v0$5;
							}
						}
					}
				}
				return list;
			}
			var _v1 = _v0.b;
			var x = _v1.a;
			return _List_fromArray(
				[x]);
		}
	});
var $elm$core$List$take = F2(
	function (n, list) {
		return A3($elm$core$List$takeFast, 0, n, list);
	});
var $elm_community$list_extra$List$Extra$removeAt = F2(
	function (index, l) {
		if (index < 0) {
			return l;
		} else {
			var _v0 = A2($elm$core$List$drop, index, l);
			if (!_v0.b) {
				return l;
			} else {
				var rest = _v0.b;
				return _Utils_ap(
					A2($elm$core$List$take, index, l),
					rest);
			}
		}
	});
var $elm$browser$Browser$Navigation$replaceUrl = _Browser_replaceUrl;
var $elm$json$Json$Encode$null = _Json_encodeNull;
var $author$project$Main$requestLocation = _Platform_outgoingPort(
	'requestLocation',
	function ($) {
		return $elm$json$Json$Encode$null;
	});
var $author$project$Main$requestSplitsGpx = _Platform_outgoingPort('requestSplitsGpx', $elm$json$Json$Encode$string);
var $author$project$Main$storeState = _Platform_outgoingPort('storeState', $elm$json$Json$Encode$string);
var $author$project$Main$restoreState = F2(
	function (jsonString, model) {
		var _v0 = A2($elm$json$Json$Decode$decodeString, $author$project$Main$stateDecoder, jsonString);
		if (!_v0.$) {
			var decoded = _v0.a;
			var restored = _Utils_update(
				model,
				{
					o: $author$project$Main$withLiveSplit(
						_Utils_update(
							decoded,
							{ai: model.o.ai}))
				});
			return _Utils_Tuple2(
				restored,
				$elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							$author$project$Main$storeState(
							$author$project$Main$encodeSavedState(restored.o)),
							$author$project$Main$requestSplitCmd(restored.o)
						])));
		} else {
			var err = _v0.a;
			var s = model.o;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						o: _Utils_update(
							s,
							{
								ab: $elm$core$Maybe$Just(
									$elm$json$Json$Decode$errorToString(err))
							})
					}),
				$elm$core$Platform$Cmd$none);
		}
	});
var $elm$core$Basics$always = F2(
	function (a, _v0) {
		return a;
	});
var $elm_community$list_extra$List$Extra$updateAt = F3(
	function (index, fn, list) {
		if (index < 0) {
			return list;
		} else {
			var tail = A2($elm$core$List$drop, index, list);
			if (tail.b) {
				var x = tail.a;
				var xs = tail.b;
				return _Utils_ap(
					A2($elm$core$List$take, index, list),
					A2(
						$elm$core$List$cons,
						fn(x),
						xs));
			} else {
				return list;
			}
		}
	});
var $elm_community$list_extra$List$Extra$setAt = F2(
	function (index, value) {
		return A2(
			$elm_community$list_extra$List$Extra$updateAt,
			index,
			$elm$core$Basics$always(value));
	});
var $author$project$Main$sortWaypointIndices = F2(
	function (editableWps, indices) {
		return A2(
			$elm$core$List$sortBy,
			function (idx) {
				return A2(
					$elm$core$Maybe$withDefault,
					0,
					A2(
						$elm$core$Maybe$map,
						A2(
							$elm$core$Basics$composeR,
							$author$project$Main$effectiveWaypoint,
							function ($) {
								return $.az;
							}),
						A2($elm_community$list_extra$List$Extra$getAt, idx, editableWps)));
			},
			indices);
	});
var $elm$file$File$toString = _File_toString;
var $elm$core$String$trim = _String_trim;
var $author$project$Main$updateAndStoreModel = function (model) {
	return _Utils_Tuple2(
		model,
		$author$project$Main$storeState(
			$author$project$Main$encodeSavedState(model.o)));
};
var $author$project$Zipper$updateCurrent = F2(
	function (update, zipper) {
		return A3(
			$author$project$Zipper$Zipper,
			zipper.as,
			update(zipper.c),
			zipper.aF);
	});
var $author$project$Main$updateEditableWaypoint = F3(
	function (track, i, fn) {
		return _Utils_update(
			track,
			{
				f: A3($elm_community$list_extra$List$Extra$updateAt, i, fn, track.f)
			});
	});
var $author$project$Main$updateOverrides = F2(
	function (fn, ew) {
		return _Utils_update(
			ew,
			{
				k: fn(ew.k)
			});
	});
var $author$project$Main$update = F2(
	function (msg, model) {
		var updateState = function (newState) {
			return _Utils_update(
				model,
				{o: newState});
		};
		var updateSplitAndStore = function (newModel) {
			var state = $author$project$Main$withLiveSplit(newModel.o);
			return _Utils_Tuple2(
				_Utils_update(
					newModel,
					{o: state}),
				$elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[
							$author$project$Main$storeState(
							$author$project$Main$encodeSavedState(state)),
							$author$project$Main$requestSplitCmd(state)
						])));
		};
		var s = model.o;
		switch (msg.$) {
			case 0:
				return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
			case 1:
				return _Utils_Tuple2(
					updateState(
						_Utils_update(
							s,
							{ab: $elm$core$Maybe$Nothing})),
					$elm$core$Platform$Cmd$none);
			case 2:
				var show = msg.a;
				return _Utils_Tuple2(
					updateState(
						_Utils_update(
							s,
							{_: show})),
					$elm$core$Platform$Cmd$none);
			case 10:
				var tab = msg.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{K: tab})));
			case 3:
				return _Utils_Tuple2(
					model,
					A2(
						$elm$file$File$Select$file,
						_List_fromArray(
							['application/gpx+xml']),
						$author$project$Main$FileUploaded));
			case 4:
				var file = msg.a;
				return A2(
					$elm$core$Tuple$mapSecond,
					function (cmd) {
						return $elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									cmd,
									A2(
									$elm$core$Task$perform,
									$author$project$Main$GPXStringed,
									$elm$file$File$toString(file))
								]));
					},
					$author$project$Main$updateAndStoreModel(
						updateState(
							_Utils_update(
								s,
								{b: $author$project$Main$Loading}))));
			case 5:
				var gpxContent = msg.a;
				return _Utils_Tuple2(
					model,
					$author$project$Main$calculateElevationProfileData(gpxContent));
			case 6:
				var string = msg.a;
				var _v1 = A2(
					$elm$json$Json$Decode$decodeString,
					$author$project$GpxApi$decodeResult($author$project$GpxApi$decodeElevationProfileDataResponse),
					string);
				if (_v1.$ === 1) {
					var errMsg = _v1.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									b: $author$project$Main$Error(
										'parsing result from GPX response: ' + $elm$json$Json$Decode$errorToString(errMsg))
								})));
				} else {
					var typedResult = _v1.a;
					if (typedResult.$ === 1) {
						var errMsg = typedResult.a;
						return updateSplitAndStore(
							updateState(
								_Utils_update(
									s,
									{
										b: $author$project$Main$Error('getting profile data from GPX: ' + errMsg)
									})));
					} else {
						var gpxTracks = typedResult.a;
						return updateSplitAndStore(
							updateState(
								_Utils_update(
									s,
									{
										a: function () {
											var ep = s.a;
											return _Utils_update(
												ep,
												{l: _List_Nil});
										}(),
										d: $author$project$Main$initialFilteredCategories(
											A2(
												$elm$core$List$concatMap,
												function ($) {
													return $.bP;
												},
												gpxTracks)),
										b: function () {
											var _v3 = $author$project$Zipper$fromList(
												A2($elm$core$List$map, $author$project$Main$editableTrackFromGpxTrack, gpxTracks));
											if (_v3.$ === 1) {
												return $author$project$Main$Error('No tracks available in uploaded GPX');
											} else {
												var positionalTracks = _v3.a;
												return $author$project$Main$Loaded(positionalTracks);
											}
										}()
									})));
					}
				}
			case 7:
				var string = msg.a;
				var _v4 = A2(
					$elm$json$Json$Decode$decodeString,
					$author$project$GpxApi$decodeResult($author$project$GpxApi$decodeSplitResult),
					string);
				if (_v4.$ === 1) {
					var errMsg = _v4.a;
					return _Utils_Tuple2(
						updateState(
							_Utils_update(
								s,
								{I: $elm$core$Maybe$Nothing})),
						$author$project$Main$logError(
							'parsing split profile response: ' + $elm$json$Json$Decode$errorToString(errMsg)));
				} else {
					var typedResult = _v4.a;
					if (typedResult.$ === 1) {
						var errMsg = typedResult.a;
						return _Utils_Tuple2(
							updateState(
								_Utils_update(
									s,
									{I: $elm$core$Maybe$Nothing})),
							$author$project$Main$logError('splitting profile: ' + errMsg));
					} else {
						var splitResult = typedResult.a;
						return _Utils_Tuple2(
							updateState(
								_Utils_update(
									s,
									{
										I: $elm$core$Maybe$Just(splitResult)
									})),
							$elm$core$Platform$Cmd$none);
					}
				}
			case 8:
				var _v6 = s.b;
				if (_v6.$ === 3) {
					var tracks = _v6.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									b: $author$project$Main$Loaded(
										$author$project$Zipper$navigatePrevious(tracks))
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 9:
				var _v7 = s.b;
				if (_v7.$ === 3) {
					var tracks = _v7.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									b: $author$project$Main$Loaded(
										$author$project$Zipper$navigateNext(tracks))
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 12:
				return _Utils_Tuple2(
					model,
					$author$project$Main$requestLocation(0));
			case 13:
				var nowEnabled = !s.y;
				return nowEnabled ? A2(
					$elm$core$Tuple$mapSecond,
					function (cmd) {
						return $elm$core$Platform$Cmd$batch(
							_List_fromArray(
								[
									cmd,
									$author$project$Main$requestLocation(0)
								]));
					},
					$author$project$Main$updateAndStoreModel(
						updateState(
							_Utils_update(
								s,
								{y: true})))) : $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{y: false})));
			case 14:
				var interval = msg.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{U: interval})));
			case 15:
				return _Utils_Tuple2(
					model,
					$author$project$Main$requestLocation(0));
			case 11:
				var value = msg.a;
				var _v8 = A2($elm$json$Json$Decode$decodeValue, $author$project$Location$decodeLocationResult, value);
				if (!_v8.$) {
					if (!_v8.a.$) {
						var pos = _v8.a.a;
						var _v9 = s.b;
						if (_v9.$ === 3) {
							var tracks = _v9.a;
							var gpsPos = A2($author$project$Location$LatLon, pos.bh, pos.bi);
							var nearest = A2($author$project$Location$findNearestTrackPoint, gpsPos, tracks.c.bM);
							var matchedDist = A2(
								$elm$core$Maybe$withDefault,
								0,
								A2(
									$elm$core$Maybe$map,
									function ($) {
										return $.az;
									},
									nearest));
							var offRouteDist = A2(
								$elm$core$Maybe$withDefault,
								0,
								A2(
									$elm$core$Maybe$map,
									function (tp) {
										return A2(
											$author$project$Location$haversineDistance,
											gpsPos,
											A2($author$project$Location$LatLon, tp.bh, tp.bi));
									},
									nearest));
							return _Utils_Tuple2(
								updateState(
									$author$project$Main$withLiveSplit(
										_Utils_update(
											s,
											{
												ag: $elm$core$Maybe$Just(
													A4($author$project$Location$LocationState, gpsPos, pos.a_, matchedDist, offRouteDist)),
												Y: $elm$core$Maybe$Nothing,
												cg: $elm$core$Maybe$Just(matchedDist)
											}))),
								$elm$core$Platform$Cmd$none);
						} else {
							return _Utils_Tuple2(
								updateState(
									_Utils_update(
										s,
										{Y: $elm$core$Maybe$Nothing})),
								$elm$core$Platform$Cmd$none);
						}
					} else {
						var locErr = _v8.a.a;
						return _Utils_Tuple2(
							updateState(
								_Utils_update(
									s,
									{
										Y: $elm$core$Maybe$Just(locErr)
									})),
							$elm$core$Platform$Cmd$none);
					}
				} else {
					return _Utils_Tuple2(
						updateState(
							_Utils_update(
								s,
								{
									Y: $elm$core$Maybe$Just(1)
								})),
						$elm$core$Platform$Cmd$none);
				}
			case 16:
				var category = msg.a;
				var enabled = msg.b;
				var newCategories = A3($elm$core$Dict$insert, category, enabled, s.d);
				return updateSplitAndStore(
					updateState(
						$author$project$Main$correctWaypointSelectionInState(
							_Utils_update(
								s,
								{d: newCategories}))));
			case 17:
				var enabled = msg.a;
				return updateSplitAndStore(
					updateState(
						$author$project$Main$correctWaypointSelectionInState(
							_Utils_update(
								s,
								{z: enabled}))));
			case 18:
				var enabled = msg.a;
				return updateSplitAndStore(
					updateState(
						$author$project$Main$correctWaypointSelectionInState(
							_Utils_update(
								s,
								{
									d: A2(
										$elm$core$Dict$map,
										F2(
											function (_v10, _v11) {
												return enabled;
											}),
										s.d)
								}))));
			case 20:
				var i = msg.a;
				var name = msg.b;
				var _v12 = s.b;
				if (_v12.$ === 3) {
					var tracks = _v12.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									b: $author$project$Main$Loaded(
										A2(
											$author$project$Zipper$updateCurrent,
											function (current) {
												return A3(
													$author$project$Main$updateEditableWaypoint,
													current,
													i,
													function (ew) {
														return A2(
															$author$project$Main$updateOverrides,
															function (o) {
																return _Utils_update(
																	o,
																	{
																		bn: $elm$core$Maybe$Just(name)
																	});
															},
															ew);
													});
											},
											tracks))
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 19:
				var i = msg.a;
				var dist = msg.b;
				var _v13 = s.b;
				if (_v13.$ === 3) {
					var tracks = _v13.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									b: $author$project$Main$Loaded(
										A2(
											$author$project$Zipper$updateCurrent,
											function (current) {
												return A3(
													$author$project$Main$updateEditableWaypoint,
													current,
													i,
													function (ew) {
														return A2(
															$author$project$Main$updateOverrides,
															function (o) {
																return _Utils_update(
																	o,
																	{
																		az: $elm$core$Maybe$Just(dist)
																	});
															},
															ew);
													});
											},
											tracks))
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 21:
				var i = msg.a;
				var deleted = msg.b;
				var _v14 = s.b;
				if (_v14.$ === 3) {
					var tracks = _v14.a;
					var ep = s.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									a: _Utils_update(
										ep,
										{
											l: deleted ? A2(
												$elm$core$List$filter,
												function (idx) {
													return !_Utils_eq(idx, i);
												},
												ep.l) : ep.l
										}),
									b: $author$project$Main$Loaded(
										A2(
											$author$project$Zipper$updateCurrent,
											function (current) {
												return A3(
													$author$project$Main$updateEditableWaypoint,
													current,
													i,
													function (ew) {
														return _Utils_update(
															ew,
															{L: deleted});
													});
											},
											tracks))
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 22:
				var i = msg.a;
				var cat = msg.b;
				var add = msg.c;
				var _v15 = s.b;
				if (_v15.$ === 3) {
					var tracks = _v15.a;
					var updateCats = function (ew) {
						var o = ew.k;
						var currentCats = A2($elm$core$Maybe$withDefault, ew.x.a1, ew.k.a1);
						return _Utils_update(
							ew,
							{
								k: _Utils_update(
									o,
									{
										a1: $elm$core$Maybe$Just(
											add ? (A2($elm$core$List$member, cat, currentCats) ? currentCats : _Utils_ap(
												currentCats,
												_List_fromArray(
													[cat]))) : A2(
												$elm$core$List$filter,
												function (c) {
													return !_Utils_eq(c, cat);
												},
												currentCats))
									})
							});
					};
					var newTracks = A2(
						$author$project$Zipper$updateCurrent,
						function (current) {
							return A3($author$project$Main$updateEditableWaypoint, current, i, updateCats);
						},
						tracks);
					var allEffectiveWaypoints = A2(
						$elm$core$List$concatMap,
						A2(
							$elm$core$Basics$composeR,
							function ($) {
								return $.f;
							},
							$author$project$Main$effectiveWaypoints),
						_Utils_ap(
							newTracks.as,
							_Utils_ap(
								_List_fromArray(
									[newTracks.c]),
								newTracks.aF)));
					var newFilteredCategories = function () {
						if (add) {
							return A2($elm$core$Dict$member, cat, s.d) ? s.d : A3($elm$core$Dict$insert, cat, true, s.d);
						} else {
							var catStillUsed = A2(
								$elm$core$List$any,
								function (w) {
									return A2($elm$core$List$member, cat, w.a1);
								},
								allEffectiveWaypoints);
							return catStillUsed ? s.d : A2($elm$core$Dict$remove, cat, s.d);
						}
					}();
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									d: newFilteredCategories,
									b: $author$project$Main$Loaded(newTracks)
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 24:
				var i = msg.a;
				var value = msg.b;
				return _Utils_Tuple2(
					updateState(
						_Utils_update(
							s,
							{
								Q: A3($elm$core$Dict$insert, i, value, s.Q)
							})),
					$elm$core$Platform$Cmd$none);
			case 23:
				var i = msg.a;
				var trimmed = $elm$core$String$trim(
					A2(
						$elm$core$Maybe$withDefault,
						'',
						A2($elm$core$Dict$get, i, s.Q)));
				if ($elm$core$String$isEmpty(trimmed)) {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				} else {
					var _v16 = s.b;
					if (_v16.$ === 3) {
						var tracks = _v16.a;
						var updateCats = function (ew) {
							var o = ew.k;
							var currentCats = A2($elm$core$Maybe$withDefault, ew.x.a1, ew.k.a1);
							return A2($elm$core$List$member, trimmed, currentCats) ? ew : _Utils_update(
								ew,
								{
									k: _Utils_update(
										o,
										{
											a1: $elm$core$Maybe$Just(
												_Utils_ap(
													currentCats,
													_List_fromArray(
														[trimmed])))
										})
								});
						};
						var newFilteredCategories = A2($elm$core$Dict$member, trimmed, s.d) ? s.d : A3($elm$core$Dict$insert, trimmed, true, s.d);
						return updateSplitAndStore(
							updateState(
								_Utils_update(
									s,
									{
										d: newFilteredCategories,
										Q: A2($elm$core$Dict$remove, i, s.Q),
										b: $author$project$Main$Loaded(
											A2(
												$author$project$Zipper$updateCurrent,
												function (current) {
													return A3($author$project$Main$updateEditableWaypoint, current, i, updateCats);
												},
												tracks))
									})));
					} else {
						return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
					}
				}
			case 25:
				var _v17 = s.b;
				if (_v17.$ === 3) {
					var tracks = _v17.a;
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									b: $author$project$Main$Loaded(
										A2(
											$author$project$Zipper$updateCurrent,
											function (current) {
												return _Utils_update(
													current,
													{
														f: A2(
															$elm$core$List$map,
															function (ew) {
																return _Utils_update(
																	ew,
																	{L: false, k: $author$project$Main$emptyOverrides});
															},
															current.f)
													});
											},
											tracks))
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 26:
				var size = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{W: size})
							})));
			case 27:
				var height = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{ac: height})
							})));
			case 28:
				var thickness = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{ad: thickness})
							})));
			case 29:
				var gain = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{X: gain})
							})));
			case 30:
				var show = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{G: show})
							})));
			case 31:
				var tau = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{O: tau})
							})));
			case 42:
				var pos = msg.a;
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{ag: $elm$core$Maybe$Nothing, cg: pos})));
			case 32:
				var n = msg.a;
				var ep = s.a;
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{aa: n})
							})));
			case 33:
				var mode = msg.a;
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{q: mode})));
			case 34:
				var mode = msg.a;
				var ep = s.a;
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{J: mode})
							})));
			case 35:
				var ep = s.a;
				var indices = ep.l;
				var editableWps = A2(
					$elm$core$Maybe$withDefault,
					_List_Nil,
					A2(
						$elm$core$Maybe$map,
						A2(
							$elm$core$Basics$composeR,
							function ($) {
								return $.c;
							},
							function ($) {
								return $.f;
							}),
						$author$project$Main$maybeFromloadableResource(s.b)));
				var availableIndices = A2(
					$elm$core$List$map,
					$elm$core$Tuple$first,
					$author$project$Main$indexedEffectiveWaypoints(editableWps));
				var firstAvailable = $elm$core$List$head(
					A2(
						$elm$core$List$filter,
						function (i) {
							return !A2($elm$core$List$member, i, indices);
						},
						availableIndices));
				if (!firstAvailable.$) {
					var idx = firstAvailable.a;
					var newIndices = A2(
						$author$project$Main$sortWaypointIndices,
						editableWps,
						A2($elm$core$List$cons, idx, indices));
					return updateSplitAndStore(
						updateState(
							_Utils_update(
								s,
								{
									a: _Utils_update(
										ep,
										{l: newIndices})
								})));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 36:
				var splitListPos = msg.a;
				var newWaypointIdx = msg.b;
				var ep = s.a;
				var newIndices = A2(
					$elm$core$Maybe$withDefault,
					_List_Nil,
					A2(
						$elm$core$Maybe$map,
						A2(
							$elm$core$Basics$composeR,
							function ($) {
								return $.c;
							},
							A2(
								$elm$core$Basics$composeR,
								function ($) {
									return $.f;
								},
								function (editableWaypoints) {
									return A2(
										$author$project$Main$sortWaypointIndices,
										editableWaypoints,
										A3($elm_community$list_extra$List$Extra$setAt, splitListPos, newWaypointIdx, ep.l));
								})),
						$author$project$Main$maybeFromloadableResource(s.b)));
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{l: newIndices})
							})));
			case 37:
				var splitListPos = msg.a;
				var ep = s.a;
				var newIndices = A2($elm_community$list_extra$List$Extra$removeAt, splitListPos, ep.l);
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{l: newIndices})
							})));
			case 38:
				var val = msg.a;
				var ep = s.a;
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{B: val})
							})));
			case 39:
				var val = msg.a;
				var ep = s.a;
				return updateSplitAndStore(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{C: val})
							})));
			case 40:
				var maybeInterval = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{M: maybeInterval})
							})));
			case 41:
				var show = msg.a;
				var ep = s.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								a: _Utils_update(
									ep,
									{N: show})
							})));
			case 43:
				var maybeSelection = msg.a;
				return A2(
					$elm$core$Maybe$withDefault,
					_Utils_Tuple2(model, $elm$core$Platform$Cmd$none),
					A2(
						$elm$core$Maybe$map,
						function (selection) {
							var cs = s.e;
							return $author$project$Main$updateAndStoreModel(
								updateState(
									_Utils_update(
										s,
										{
											e: _Utils_update(
												cs,
												{h: selection})
										})));
						},
						maybeSelection));
			case 44:
				var point = msg.a;
				var cs = s.e;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								e: _Utils_update(
									cs,
									{t: point})
							})));
			case 45:
				var spacing = msg.a;
				var cs = s.e;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								e: _Utils_update(
									cs,
									{m: spacing})
							})));
			case 46:
				var detail = msg.a;
				var cs = s.e;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								e: _Utils_update(
									cs,
									{A: detail})
							})));
			case 47:
				var show = msg.a;
				var cs = s.e;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								e: _Utils_update(
									cs,
									{H: show})
							})));
			case 48:
				var show = msg.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{S: show})));
			case 49:
				var idx = msg.a;
				var cs = s.e;
				var newDisplay = function () {
					var _v19 = cs.h;
					switch (_v19.$) {
						case 3:
							return $author$project$Main$ToWaypoint(idx);
						case 4:
							return $author$project$Main$FromWaypoint(idx);
						default:
							var other = _v19;
							return other;
					}
				}();
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{
								e: _Utils_update(
									cs,
									{h: newDisplay})
							})));
			case 50:
				var threshold = msg.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{w: threshold})));
			case 51:
				var show = msg.a;
				return $author$project$Main$updateAndStoreModel(
					updateState(
						_Utils_update(
							s,
							{T: show})));
			case 52:
				return _Utils_Tuple2(
					model,
					$author$project$Main$downloadState(
						$author$project$Main$encodeSavedState(
							_Utils_update(
								s,
								{_: false}))));
			case 53:
				var _v20 = s.I;
				if (!_v20.$) {
					var splitResult = _v20.a;
					return _Utils_Tuple2(
						model,
						$author$project$Main$requestSplitsGpx(
							A2(
								$elm$json$Json$Encode$encode,
								0,
								A2($elm$json$Json$Encode$list, $author$project$GpxApi$encodeTrack, splitResult.ck))));
				} else {
					return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
				}
			case 54:
				return _Utils_Tuple2(
					model,
					A2(
						$elm$file$File$Select$file,
						_List_fromArray(
							['application/json']),
						$author$project$Main$StateFileSelected));
			case 55:
				var file = msg.a;
				return _Utils_Tuple2(
					model,
					A2(
						$elm$core$Task$perform,
						$author$project$Main$StateFileRead,
						$elm$file$File$toString(file)));
			case 56:
				var jsonString = msg.a;
				return A2($author$project$Main$restoreState, jsonString, model);
			case 57:
				var url = msg.a;
				return _Utils_Tuple2(
					model,
					$elm$http$Http$get(
						{
							a9: $elm$http$Http$expectString($author$project$Main$StateUrlFetched),
							bN: url
						}));
			case 58:
				if (!msg.a.$) {
					var jsonString = msg.a.a;
					return A2(
						$elm$core$Tuple$mapSecond,
						function (cmd) {
							return $elm$core$Platform$Cmd$batch(
								_List_fromArray(
									[
										cmd,
										A2($elm$browser$Browser$Navigation$replaceUrl, model.aP.bf, model.aP.a0)
									]));
						},
						A2($author$project$Main$restoreState, jsonString, model));
				} else {
					var err = msg.a.a;
					return _Utils_Tuple2(
						updateState(
							_Utils_update(
								s,
								{
									ab: $elm$core$Maybe$Just(
										'Failed to fetch state from URL: ' + function () {
											switch (err.$) {
												case 0:
													var u = err.a;
													return 'Bad URL: ' + u;
												case 1:
													return 'Request timed out';
												case 2:
													return 'Network error (check CORS headers)';
												case 3:
													var status = err.a;
													return 'HTTP ' + $elm$core$String$fromInt(status);
												default:
													var body = err.a;
													return 'Bad response: ' + body;
											}
										}())
								})),
						$elm$core$Platform$Cmd$none);
				}
			default:
				var width = msg.a;
				return (width >= 2) ? _Utils_Tuple2(
					updateState(
						_Utils_update(
							s,
							{
								ai: $elm$core$Maybe$Just(width)
							})),
					$elm$core$Platform$Cmd$none) : _Utils_Tuple2(
					model,
					$author$project$Main$logError(
						'[profile-bug] ignored bad profile width: ' + $elm$core$String$fromInt(width)));
		}
	});
var $elm$browser$Browser$Document = F2(
	function (title, body) {
		return {bV: body, cs: title};
	});
var $elm$html$Html$Attributes$stringProperty = F2(
	function (key, string) {
		return A2(
			_VirtualDom_property,
			key,
			$elm$json$Json$Encode$string(string));
	});
var $elm$html$Html$Attributes$class = $elm$html$Html$Attributes$stringProperty('className');
var $elm$html$Html$div = _VirtualDom_node('div');
var $elm$html$Html$p = _VirtualDom_node('p');
var $elm$core$Basics$negate = function (n) {
	return -n;
};
var $elm$core$String$right = F2(
	function (n, string) {
		return (n < 1) ? '' : A3(
			$elm$core$String$slice,
			-n,
			$elm$core$String$length(string),
			string);
	});
var $elm$virtual_dom$VirtualDom$style = _VirtualDom_style;
var $elm$html$Html$Attributes$style = $elm$virtual_dom$VirtualDom$style;
var $elm$virtual_dom$VirtualDom$text = _VirtualDom_text;
var $elm$html$Html$text = $elm$virtual_dom$VirtualDom$text;
var $author$project$Main$displayIsPercent = function (mode) {
	switch (mode.$) {
		case 5:
			return true;
		case 6:
			return true;
		default:
			return false;
	}
};
var $author$project$Main$safePercent = F2(
	function (part, total) {
		return (total > 0) ? $elm$core$Maybe$Just((part / total) * 100) : $elm$core$Maybe$Nothing;
	});
var $author$project$Main$displayedDistanceValue = F5(
	function (mode, finishDist, referencePoint, refWaypoint, distance) {
		switch (mode.$) {
			case 7:
				return $elm$core$Maybe$Nothing;
			case 0:
				return $elm$core$Maybe$Just(distance);
			case 1:
				return $elm$core$Maybe$Just(finishDist - distance);
			case 2:
				return $elm$core$Maybe$Just(referencePoint - distance);
			case 3:
				return A2(
					$elm$core$Maybe$map,
					function (rw) {
						return rw.az - distance;
					},
					refWaypoint);
			case 4:
				return A2(
					$elm$core$Maybe$map,
					function (rw) {
						return distance - rw.az;
					},
					refWaypoint);
			case 5:
				return A2($author$project$Main$safePercent, distance, finishDist);
			default:
				return A2($author$project$Main$safePercent, finishDist - distance, finishDist);
		}
	});
var $elm$svg$Svg$Attributes$dominantBaseline = _VirtualDom_attribute('dominant-baseline');
var $elm$svg$Svg$Attributes$dy = _VirtualDom_attribute('dy');
var $elm$svg$Svg$Attributes$fill = _VirtualDom_attribute('fill');
var $elm$svg$Svg$Attributes$fontSize = _VirtualDom_attribute('font-size');
var $elm$core$Basics$abs = function (n) {
	return (n < 0) ? (-n) : n;
};
var $elm$core$String$foldr = _String_foldr;
var $elm$core$String$toList = function (string) {
	return A3($elm$core$String$foldr, $elm$core$List$cons, _List_Nil, string);
};
var $myrho$elm_round$Round$addSign = F2(
	function (signed, str) {
		var isNotZero = A2(
			$elm$core$List$any,
			function (c) {
				return (c !== '0') && (c !== '.');
			},
			$elm$core$String$toList(str));
		return _Utils_ap(
			(signed && isNotZero) ? '-' : '',
			str);
	});
var $elm$core$String$fromFloat = _String_fromNumber;
var $elm$core$String$cons = _String_cons;
var $elm$core$Char$fromCode = _Char_fromCode;
var $myrho$elm_round$Round$increaseNum = function (_v0) {
	var head = _v0.a;
	var tail = _v0.b;
	if (head === '9') {
		var _v1 = $elm$core$String$uncons(tail);
		if (_v1.$ === 1) {
			return '01';
		} else {
			var headtail = _v1.a;
			return A2(
				$elm$core$String$cons,
				'0',
				$myrho$elm_round$Round$increaseNum(headtail));
		}
	} else {
		var c = $elm$core$Char$toCode(head);
		return ((c >= 48) && (c < 57)) ? A2(
			$elm$core$String$cons,
			$elm$core$Char$fromCode(c + 1),
			tail) : '0';
	}
};
var $elm$core$Basics$isInfinite = _Basics_isInfinite;
var $elm$core$Basics$isNaN = _Basics_isNaN;
var $elm$core$String$fromChar = function (_char) {
	return A2($elm$core$String$cons, _char, '');
};
var $elm$core$Bitwise$and = _Bitwise_and;
var $elm$core$Bitwise$shiftRightBy = _Bitwise_shiftRightBy;
var $elm$core$String$repeatHelp = F3(
	function (n, chunk, result) {
		return (n <= 0) ? result : A3(
			$elm$core$String$repeatHelp,
			n >> 1,
			_Utils_ap(chunk, chunk),
			(!(n & 1)) ? result : _Utils_ap(result, chunk));
	});
var $elm$core$String$repeat = F2(
	function (n, chunk) {
		return A3($elm$core$String$repeatHelp, n, chunk, '');
	});
var $elm$core$String$padRight = F3(
	function (n, _char, string) {
		return _Utils_ap(
			string,
			A2(
				$elm$core$String$repeat,
				n - $elm$core$String$length(string),
				$elm$core$String$fromChar(_char)));
	});
var $elm$core$String$reverse = _String_reverse;
var $myrho$elm_round$Round$splitComma = function (str) {
	var _v0 = A2($elm$core$String$split, '.', str);
	if (_v0.b) {
		if (_v0.b.b) {
			var before = _v0.a;
			var _v1 = _v0.b;
			var after = _v1.a;
			return _Utils_Tuple2(before, after);
		} else {
			var before = _v0.a;
			return _Utils_Tuple2(before, '0');
		}
	} else {
		return _Utils_Tuple2('0', '0');
	}
};
var $elm$core$Tuple$mapFirst = F2(
	function (func, _v0) {
		var x = _v0.a;
		var y = _v0.b;
		return _Utils_Tuple2(
			func(x),
			y);
	});
var $myrho$elm_round$Round$toDecimal = function (fl) {
	var _v0 = A2(
		$elm$core$String$split,
		'e',
		$elm$core$String$fromFloat(
			$elm$core$Basics$abs(fl)));
	if (_v0.b) {
		if (_v0.b.b) {
			var num = _v0.a;
			var _v1 = _v0.b;
			var exp = _v1.a;
			var e = A2(
				$elm$core$Maybe$withDefault,
				0,
				$elm$core$String$toInt(
					A2($elm$core$String$startsWith, '+', exp) ? A2($elm$core$String$dropLeft, 1, exp) : exp));
			var _v2 = $myrho$elm_round$Round$splitComma(num);
			var before = _v2.a;
			var after = _v2.b;
			var total = _Utils_ap(before, after);
			var zeroed = (e < 0) ? A2(
				$elm$core$Maybe$withDefault,
				'0',
				A2(
					$elm$core$Maybe$map,
					function (_v3) {
						var a = _v3.a;
						var b = _v3.b;
						return a + ('.' + b);
					},
					A2(
						$elm$core$Maybe$map,
						$elm$core$Tuple$mapFirst($elm$core$String$fromChar),
						$elm$core$String$uncons(
							_Utils_ap(
								A2(
									$elm$core$String$repeat,
									$elm$core$Basics$abs(e),
									'0'),
								total))))) : A3($elm$core$String$padRight, e + 1, '0', total);
			return _Utils_ap(
				(fl < 0) ? '-' : '',
				zeroed);
		} else {
			var num = _v0.a;
			return _Utils_ap(
				(fl < 0) ? '-' : '',
				num);
		}
	} else {
		return '';
	}
};
var $myrho$elm_round$Round$roundFun = F3(
	function (functor, s, fl) {
		if ($elm$core$Basics$isInfinite(fl) || $elm$core$Basics$isNaN(fl)) {
			return $elm$core$String$fromFloat(fl);
		} else {
			var signed = fl < 0;
			var _v0 = $myrho$elm_round$Round$splitComma(
				$myrho$elm_round$Round$toDecimal(
					$elm$core$Basics$abs(fl)));
			var before = _v0.a;
			var after = _v0.b;
			var r = $elm$core$String$length(before) + s;
			var normalized = _Utils_ap(
				A2($elm$core$String$repeat, (-r) + 1, '0'),
				A3(
					$elm$core$String$padRight,
					r,
					'0',
					_Utils_ap(before, after)));
			var totalLen = $elm$core$String$length(normalized);
			var roundDigitIndex = A2($elm$core$Basics$max, 1, r);
			var increase = A2(
				functor,
				signed,
				A3($elm$core$String$slice, roundDigitIndex, totalLen, normalized));
			var remains = A3($elm$core$String$slice, 0, roundDigitIndex, normalized);
			var num = increase ? $elm$core$String$reverse(
				A2(
					$elm$core$Maybe$withDefault,
					'1',
					A2(
						$elm$core$Maybe$map,
						$myrho$elm_round$Round$increaseNum,
						$elm$core$String$uncons(
							$elm$core$String$reverse(remains))))) : remains;
			var numLen = $elm$core$String$length(num);
			var numZeroed = (num === '0') ? num : ((s <= 0) ? _Utils_ap(
				num,
				A2(
					$elm$core$String$repeat,
					$elm$core$Basics$abs(s),
					'0')) : ((_Utils_cmp(
				s,
				$elm$core$String$length(after)) < 0) ? (A3($elm$core$String$slice, 0, numLen - s, num) + ('.' + A3($elm$core$String$slice, numLen - s, numLen, num))) : _Utils_ap(
				before + '.',
				A3($elm$core$String$padRight, s, '0', after))));
			return A2($myrho$elm_round$Round$addSign, signed, numZeroed);
		}
	});
var $myrho$elm_round$Round$round = $myrho$elm_round$Round$roundFun(
	F2(
		function (signed, str) {
			var _v0 = $elm$core$String$uncons(str);
			if (_v0.$ === 1) {
				return false;
			} else {
				if ('5' === _v0.a.a) {
					if (_v0.a.b === '') {
						var _v1 = _v0.a;
						return !signed;
					} else {
						var _v2 = _v0.a;
						return true;
					}
				} else {
					var _v3 = _v0.a;
					var _int = _v3.a;
					return function (i) {
						return ((i > 53) && signed) || ((i >= 53) && (!signed));
					}(
						$elm$core$Char$toCode(_int));
				}
			}
		}));
var $author$project$Main$formatM = function (metres) {
	return A2($myrho$elm_round$Round$round, 0, metres) + 'm';
};
var $author$project$Main$formatEleGainLoss = F2(
	function (gain, loss) {
		return '↑' + ($author$project$Main$formatM(gain) + (' ↓' + $author$project$Main$formatM(loss)));
	});
var $author$project$Main$formatPercent = function (pct) {
	return A2($myrho$elm_round$Round$round, 0, pct) + '%';
};
var $author$project$Main$formatEleGainLossPercent = F2(
	function (gainPct, lossPct) {
		return '↑' + ($author$project$Main$formatPercent(gainPct) + (' ↓' + $author$project$Main$formatPercent(lossPct)));
	});
var $author$project$Main$formatKm = F2(
	function (decimalPlaces, metres) {
		return A2($myrho$elm_round$Round$round, decimalPlaces, metres / 1000) + 'km';
	});
var $elm$svg$Svg$trustedNode = _VirtualDom_nodeNS('http://www.w3.org/2000/svg');
var $elm$svg$Svg$g = $elm$svg$Svg$trustedNode('g');
var $elm$svg$Svg$Attributes$height = _VirtualDom_attribute('height');
var $elm$svg$Svg$line = $elm$svg$Svg$trustedNode('line');
var $elm$core$Maybe$map2 = F3(
	function (func, ma, mb) {
		if (ma.$ === 1) {
			return $elm$core$Maybe$Nothing;
		} else {
			var a = ma.a;
			if (mb.$ === 1) {
				return $elm$core$Maybe$Nothing;
			} else {
				var b = mb.a;
				return $elm$core$Maybe$Just(
					A2(func, a, b));
			}
		}
	});
var $author$project$Main$offRouteColour = 'orangered';
var $elm$core$Basics$round = _Basics_round;
var $elm$svg$Svg$Attributes$stroke = _VirtualDom_attribute('stroke');
var $elm$svg$Svg$Attributes$strokeWidth = _VirtualDom_attribute('stroke-width');
var $elm$svg$Svg$svg = $elm$svg$Svg$trustedNode('svg');
var $elm$svg$Svg$text = $elm$virtual_dom$VirtualDom$text;
var $elm$svg$Svg$Attributes$textAnchor = _VirtualDom_attribute('text-anchor');
var $elm$svg$Svg$text_ = $elm$svg$Svg$trustedNode('text');
var $elm$svg$Svg$Attributes$transform = _VirtualDom_attribute('transform');
var $elm$svg$Svg$Attributes$viewBox = _VirtualDom_attribute('viewBox');
var $author$project$Main$InfoPosition = function (a) {
	return {$: 1, a: a};
};
var $author$project$Main$InfoWaypoint = function (a) {
	return {$: 0, a: a};
};
var $author$project$Main$Ride = F2(
	function (a, b) {
		return {$: 2, a: a, b: b};
	});
var $author$project$Main$waypointInfos = F3(
	function (positionDistance, position, waypoints) {
		var infoConstructor = function (wp) {
			return _Utils_eq(
				$elm$core$Maybe$Just(wp.az),
				positionDistance) ? $author$project$Main$InfoPosition(wp) : $author$project$Main$InfoWaypoint(wp);
		};
		return $elm$core$List$reverse(
			A3(
				$elm$core$List$foldl,
				F2(
					function (el, accum) {
						return (_Utils_cmp(el.az, position) < 0) ? accum : _Utils_Tuple2(
							$elm$core$Maybe$Just(el),
							_Utils_ap(
								A2(
									$elm$core$List$cons,
									infoConstructor(el),
									A2(
										$elm$core$Maybe$withDefault,
										_List_Nil,
										A2(
											$elm$core$Maybe$map,
											function (previous) {
												return _List_fromArray(
													[
														A2(
														$author$project$Main$Ride,
														el.az - previous.az,
														_Utils_Tuple2(el.aB - previous.aB, el.aE - previous.aE))
													]);
											},
											accum.a))),
								accum.b));
					}),
				_Utils_Tuple2($elm$core$Maybe$Nothing, _List_Nil),
				waypoints).b);
	});
var $elm$svg$Svg$Attributes$width = _VirtualDom_attribute('width');
var $elm$svg$Svg$Attributes$x = _VirtualDom_attribute('x');
var $elm$svg$Svg$Attributes$x1 = _VirtualDom_attribute('x1');
var $elm$svg$Svg$Attributes$x2 = _VirtualDom_attribute('x2');
var $elm$svg$Svg$Attributes$y = _VirtualDom_attribute('y');
var $elm$svg$Svg$Attributes$y1 = _VirtualDom_attribute('y1');
var $elm$svg$Svg$Attributes$y2 = _VirtualDom_attribute('y2');
var $author$project$Main$cuesheetSvg = function (offRouteThreshold) {
	return function (showOffRouteDistance) {
		return function (positionDistance) {
			return function (scrollPosition) {
				return function (waypoints) {
					return function (cs) {
						return function (finishDist) {
							return function (_v0) {
								return function (refPointEle) {
									return function (refWaypoint) {
										var totalGain = _v0.a;
										var totalLoss = _v0.b;
										var svgContentLeftStart = 0;
										var svgContentLeftStartString = $elm$core$String$fromInt(svgContentLeftStart);
										var lastWaypoint = $elm$core$List$head(
											$elm$core$List$reverse(waypoints));
										var info = A3($author$project$Main$waypointInfos, positionDistance, scrollPosition, waypoints);
										var svgHeight = cs.m * $elm$core$List$length(info);
										return A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('cuesheet')
												]),
											_List_fromArray(
												[
													A2(
													$elm$svg$Svg$svg,
													_List_fromArray(
														[
															$elm$svg$Svg$Attributes$width('100%'),
															$elm$svg$Svg$Attributes$height(
															$elm$core$String$fromInt(svgHeight)),
															$elm$svg$Svg$Attributes$viewBox(
															'-40 -10 240 ' + $elm$core$String$fromInt(svgHeight + cs.m))
														]),
													A2(
														$elm$core$List$indexedMap,
														F2(
															function (i, item) {
																var translate = $elm$svg$Svg$Attributes$transform(
																	'translate(0,' + ($elm$core$String$fromInt(i * cs.m) + ')'));
																var renderWaypointItem = F3(
																	function (showOffRoute, fillAttrs, waypoint) {
																		var offRouteLabel = $elm$core$String$fromInt(
																			$elm$core$Basics$round(waypoint.bo)) + 'm off';
																		var displayedDistance = A5($author$project$Main$displayedDistanceValue, cs.h, finishDist, cs.t, refWaypoint, waypoint.az);
																		var isReferencePoint = _Utils_eq(
																			displayedDistance,
																			$elm$core$Maybe$Just(0));
																		var waypointEle = function () {
																			if (isReferencePoint) {
																				return $elm$core$Maybe$Nothing;
																			} else {
																				var _v5 = cs.h;
																				switch (_v5.$) {
																					case 7:
																						return $elm$core$Maybe$Nothing;
																					case 0:
																						return $elm$core$Maybe$Just(
																							A2($author$project$Main$formatEleGainLoss, waypoint.aB, waypoint.aE));
																					case 1:
																						return A2(
																							$elm$core$Maybe$map,
																							function (last) {
																								return A2($author$project$Main$formatEleGainLoss, last.aB - waypoint.aB, last.aE - waypoint.aE);
																							},
																							lastWaypoint);
																					case 2:
																						return $elm$core$Maybe$Just(
																							A2($author$project$Main$formatEleGainLoss, refPointEle.a - waypoint.aB, refPointEle.b - waypoint.aE));
																					case 3:
																						return A2(
																							$elm$core$Maybe$map,
																							function (rw) {
																								return A2($author$project$Main$formatEleGainLoss, rw.aB - waypoint.aB, rw.aE - waypoint.aE);
																							},
																							refWaypoint);
																					case 4:
																						return A2(
																							$elm$core$Maybe$map,
																							function (rw) {
																								return A2($author$project$Main$formatEleGainLoss, waypoint.aB - rw.aB, waypoint.aE - rw.aE);
																							},
																							refWaypoint);
																					case 5:
																						return A3(
																							$elm$core$Maybe$map2,
																							$author$project$Main$formatEleGainLossPercent,
																							A2($author$project$Main$safePercent, waypoint.aB, totalGain),
																							A2($author$project$Main$safePercent, waypoint.aE, totalLoss));
																					default:
																						return A3(
																							$elm$core$Maybe$map2,
																							$author$project$Main$formatEleGainLossPercent,
																							A2($author$project$Main$safePercent, totalGain - waypoint.aB, totalGain),
																							A2($author$project$Main$safePercent, totalLoss - waypoint.aE, totalLoss));
																				}
																			}
																		}();
																		var waypointDistance = isReferencePoint ? $elm$core$Maybe$Nothing : ($author$project$Main$displayIsPercent(cs.h) ? A2($elm$core$Maybe$map, $author$project$Main$formatPercent, displayedDistance) : A2(
																			$elm$core$Maybe$map,
																			$author$project$Main$formatKm(cs.A),
																			displayedDistance));
																		var waypointInfo = A2(
																			$elm$core$List$filterMap,
																			$elm$core$Basics$identity,
																			_List_fromArray(
																				[
																					A2(
																					$elm$core$Maybe$map,
																					function (s) {
																						return _Utils_Tuple2(s, _List_Nil);
																					},
																					waypointDistance),
																					A2(
																					$elm$core$Maybe$map,
																					function (s) {
																						return _Utils_Tuple2(s, _List_Nil);
																					},
																					waypointEle),
																					function () {
																					var _v4 = waypoint.a1;
																					if (!_v4.b) {
																						return $elm$core$Maybe$Nothing;
																					} else {
																						var cats = _v4;
																						return $elm$core$Maybe$Just(
																							_Utils_Tuple2(
																								A2($elm$core$String$join, ', ', cats),
																								_List_Nil));
																					}
																				}(),
																					(_Utils_cmp(waypoint.bo, offRouteThreshold) > 0) ? $elm$core$Maybe$Just(
																					_Utils_Tuple2(
																						'⚠️ ' + offRouteLabel,
																						_List_fromArray(
																							[
																								$elm$svg$Svg$Attributes$fill($author$project$Main$offRouteColour)
																							]))) : ((showOffRoute && (waypoint.bo > 0)) ? $elm$core$Maybe$Just(
																					_Utils_Tuple2(offRouteLabel, _List_Nil)) : $elm$core$Maybe$Nothing)
																				]));
																		var waypointInfoLines = $elm$core$List$isEmpty(waypointInfo) ? _List_fromArray(
																			[
																				_Utils_Tuple2('◉', _List_Nil)
																			]) : waypointInfo;
																		return A2(
																			$elm$svg$Svg$g,
																			_List_fromArray(
																				[translate]),
																			A2(
																				$elm$core$List$cons,
																				A2(
																					$elm$svg$Svg$text_,
																					_Utils_ap(
																						_List_fromArray(
																							[
																								$elm$svg$Svg$Attributes$x(
																								$elm$core$String$fromInt(svgContentLeftStart + 10)),
																								$elm$svg$Svg$Attributes$dominantBaseline('middle'),
																								$elm$svg$Svg$Attributes$y(
																								$elm$core$String$fromInt((cs.m / 2) | 0))
																							]),
																						fillAttrs),
																					_List_fromArray(
																						[
																							$elm$svg$Svg$text(waypoint.bn)
																						])),
																				A2(
																					$elm$core$List$indexedMap,
																					F2(
																						function (j, _v3) {
																							var line = _v3.a;
																							var lineAttributes = _v3.b;
																							return A2(
																								$elm$svg$Svg$text_,
																								_Utils_ap(
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$x(svgContentLeftStartString),
																											$elm$svg$Svg$Attributes$y(
																											$elm$core$String$fromInt((cs.m / 2) | 0)),
																											$elm$svg$Svg$Attributes$dominantBaseline('middle'),
																											$elm$svg$Svg$Attributes$dy(
																											$elm$core$String$fromFloat(
																												j - (($elm$core$List$length(waypointInfoLines) - 1) / 2)) + 'em'),
																											$elm$svg$Svg$Attributes$textAnchor('end'),
																											$elm$svg$Svg$Attributes$fontSize('smaller')
																										]),
																									lineAttributes),
																								_List_fromArray(
																									[
																										$elm$svg$Svg$text(line)
																									]));
																						}),
																					waypointInfoLines)));
																	});
																switch (item.$) {
																	case 0:
																		var waypoint = item.a;
																		return A3(
																			renderWaypointItem,
																			showOffRouteDistance,
																			(_Utils_cmp(waypoint.bo, offRouteThreshold) > 0) ? _List_fromArray(
																				[
																					$elm$svg$Svg$Attributes$fill($author$project$Main$offRouteColour)
																				]) : _List_Nil,
																			waypoint);
																	case 1:
																		var waypoint = item.a;
																		return A3(
																			renderWaypointItem,
																			true,
																			_List_fromArray(
																				[
																					$elm$svg$Svg$Attributes$fill('steelblue')
																				]),
																			waypoint);
																	default:
																		var dist = item.a;
																		var _v2 = item.b;
																		var gain = _v2.a;
																		var loss = _v2.b;
																		var strokeWidth = '1';
																		var arrowTop = '2';
																		var arrowHeadTop = $elm$core$String$fromInt(cs.m - 6);
																		var arrowBottom = $elm$core$String$fromInt(cs.m - 2);
																		return A2(
																			$elm$svg$Svg$g,
																			_List_fromArray(
																				[translate]),
																			_List_fromArray(
																				[
																					A2(
																					$elm$svg$Svg$line,
																					_List_fromArray(
																						[
																							$elm$svg$Svg$Attributes$x1(svgContentLeftStartString),
																							$elm$svg$Svg$Attributes$y1(arrowTop),
																							$elm$svg$Svg$Attributes$x2(svgContentLeftStartString),
																							$elm$svg$Svg$Attributes$y2(arrowBottom),
																							$elm$svg$Svg$Attributes$stroke('grey'),
																							$elm$svg$Svg$Attributes$strokeWidth(strokeWidth)
																						]),
																					_List_Nil),
																					A2(
																					$elm$svg$Svg$line,
																					_List_fromArray(
																						[
																							$elm$svg$Svg$Attributes$x1(
																							$elm$core$String$fromInt(svgContentLeftStart - 2)),
																							$elm$svg$Svg$Attributes$y1(arrowHeadTop),
																							$elm$svg$Svg$Attributes$x2(
																							$elm$core$String$fromInt(svgContentLeftStart)),
																							$elm$svg$Svg$Attributes$y2(arrowBottom),
																							$elm$svg$Svg$Attributes$stroke('grey'),
																							$elm$svg$Svg$Attributes$strokeWidth(strokeWidth)
																						]),
																					_List_Nil),
																					A2(
																					$elm$svg$Svg$line,
																					_List_fromArray(
																						[
																							$elm$svg$Svg$Attributes$x1(
																							$elm$core$String$fromInt(svgContentLeftStart + 2)),
																							$elm$svg$Svg$Attributes$y1(arrowHeadTop),
																							$elm$svg$Svg$Attributes$x2(
																							$elm$core$String$fromInt(svgContentLeftStart)),
																							$elm$svg$Svg$Attributes$y2(arrowBottom),
																							$elm$svg$Svg$Attributes$stroke('grey'),
																							$elm$svg$Svg$Attributes$strokeWidth(strokeWidth)
																						]),
																					_List_Nil),
																					A2(
																					$elm$svg$Svg$text_,
																					_List_fromArray(
																						[
																							$elm$svg$Svg$Attributes$x(
																							$elm$core$String$fromInt(svgContentLeftStart + 10)),
																							$elm$svg$Svg$Attributes$y(
																							$elm$core$String$fromInt((cs.m / 2) | 0)),
																							$elm$svg$Svg$Attributes$dominantBaseline('middle'),
																							$elm$svg$Svg$Attributes$fontSize('smaller')
																						]),
																					_List_fromArray(
																						[
																							$elm$svg$Svg$text(
																							$author$project$Main$displayIsPercent(cs.h) ? (A2(
																								$elm$core$Maybe$withDefault,
																								'',
																								A2(
																									$elm$core$Maybe$map,
																									$author$project$Main$formatPercent,
																									A2($author$project$Main$safePercent, dist, finishDist))) + (' ' + A2(
																								$author$project$Main$formatEleGainLossPercent,
																								A2(
																									$elm$core$Maybe$withDefault,
																									0,
																									A2($author$project$Main$safePercent, gain, totalGain)),
																								A2(
																									$elm$core$Maybe$withDefault,
																									0,
																									A2($author$project$Main$safePercent, loss, totalLoss))))) : (A2($author$project$Main$formatKm, cs.A, dist) + (' ' + A2($author$project$Main$formatEleGainLoss, gain, loss))))
																						]))
																				]));
																}
															}),
														info))
												]));
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $elm_community$list_extra$List$Extra$find = F2(
	function (predicate, list) {
		find:
		while (true) {
			if (!list.b) {
				return $elm$core$Maybe$Nothing;
			} else {
				var first = list.a;
				var rest = list.b;
				if (predicate(first)) {
					return $elm$core$Maybe$Just(first);
				} else {
					var $temp$predicate = predicate,
						$temp$list = rest;
					predicate = $temp$predicate;
					list = $temp$list;
					continue find;
				}
			}
		}
	});
var $author$project$Main$cumulativeGainLossAtDistance = F2(
	function (dist, trackpoints) {
		var _v0 = A2(
			$elm_community$list_extra$List$Extra$find,
			function (tp) {
				return _Utils_cmp(tp.az, dist) > -1;
			},
			trackpoints);
		if (!_v0.$) {
			var tp = _v0.a;
			return $elm$core$Result$Ok(
				_Utils_Tuple2(tp.aB, tp.aE));
		} else {
			var _v1 = $elm_community$list_extra$List$Extra$last(trackpoints);
			if (!_v1.$) {
				var tp = _v1.a;
				return $elm$core$Result$Ok(
					_Utils_Tuple2(tp.aB, tp.aE));
			} else {
				return $elm$core$Result$Err('no trackpoints found for gain/loss lookup');
			}
		}
	});
var $author$project$Main$startFinishCategory = 'Start/Finish';
var $author$project$Main$injectStartFinish = F3(
	function (finishDist, _v0, waypoints) {
		var totalGain = _v0.a;
		var totalLoss = _v0.b;
		var hasWaypointAtDistance = function (d) {
			return A2(
				$elm$core$List$any,
				function (w) {
					return _Utils_eq(w.az, d);
				},
				waypoints);
		};
		var withStart = hasWaypointAtDistance(0) ? waypoints : A2(
			$elm$core$List$cons,
			A6(
				$author$project$GpxApi$Waypoint,
				0,
				'Start',
				_List_fromArray(
					[$author$project$Main$startFinishCategory]),
				0,
				0,
				0),
			waypoints);
		return hasWaypointAtDistance(finishDist) ? withStart : _Utils_ap(
			withStart,
			_List_fromArray(
				[
					A6(
					$author$project$GpxApi$Waypoint,
					finishDist,
					'Finish',
					_List_fromArray(
						[$author$project$Main$startFinishCategory]),
					totalGain,
					totalLoss,
					0)
				]));
	});
var $author$project$Main$lastTrackpointDistance = function (trackpoints) {
	return A2(
		$elm$core$Maybe$withDefault,
		0,
		A2(
			$elm$core$Maybe$map,
			function ($) {
				return $.az;
			},
			$elm_community$list_extra$List$Extra$last(trackpoints)));
};
var $author$project$Main$liveNoPositionWarning = function (state) {
	return ((!state.q) && _Utils_eq(state.cg, $elm$core$Maybe$Nothing)) ? A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('warning_panel')
			]),
		_List_fromArray(
			[
				$elm$html$Html$text('Live view has no position — showing the whole route. Set a position or start tracking.')
			])) : $elm$html$Html$text('');
};
var $elm$core$Result$toMaybe = function (result) {
	if (!result.$) {
		var v = result.a;
		return $elm$core$Maybe$Just(v);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Main$trimWaypointCategories = function (categories) {
	return $elm$core$List$map(
		function (w) {
			var _v0 = w.a1;
			if (!_v0.b) {
				return w;
			} else {
				var cats = _v0;
				return _Utils_update(
					w,
					{
						a1: A2(
							$elm$core$List$filter,
							function (cat) {
								return A2(
									$elm$core$Maybe$withDefault,
									true,
									A2($elm$core$Dict$get, cat, categories));
							},
							cats)
					});
			}
		});
};
var $elm$core$Result$withDefault = F2(
	function (def, result) {
		if (!result.$) {
			var a = result.a;
			return a;
		} else {
			return def;
		}
	});
var $author$project$Main$viewCuesheetTab = F2(
	function (state, tracks) {
		var scrollPosition = function () {
			var _v4 = state.q;
			if (!_v4) {
				return A2($elm$core$Maybe$withDefault, 0, state.cg);
			} else {
				return 0;
			}
		}();
		var positionWaypoint = A2(
			$elm$core$Maybe$andThen,
			function (pos) {
				return A2(
					$elm$core$Maybe$map,
					function (_v3) {
						var g = _v3.a;
						var l = _v3.b;
						return A6(
							$author$project$GpxApi$Waypoint,
							pos,
							'Current position',
							_List_Nil,
							g,
							l,
							A2(
								$elm$core$Maybe$withDefault,
								0,
								A2(
									$elm$core$Maybe$map,
									function ($) {
										return $.cb;
									},
									state.ag)));
					},
					$elm$core$Result$toMaybe(
						A2($author$project$Main$cumulativeGainLossAtDistance, pos, tracks.c.bM)));
			},
			state.cg);
		var currentFinishDistance = $author$project$Main$lastTrackpointDistance(tracks.c.bM);
		var currentEffectiveWaypoints = $author$project$Main$effectiveWaypoints(tracks.c.f);
		var cs = state.e;
		var refWaypoint = function () {
			var _v2 = cs.h;
			switch (_v2.$) {
				case 3:
					var idx = _v2.a;
					return A2($elm_community$list_extra$List$Extra$getAt, idx, currentEffectiveWaypoints);
				case 4:
					var idx = _v2.a;
					return A2($elm_community$list_extra$List$Extra$getAt, idx, currentEffectiveWaypoints);
				default:
					return $elm$core$Maybe$Nothing;
			}
		}();
		var refPointEle = function () {
			if (!refWaypoint.$) {
				var wp = refWaypoint.a;
				return _Utils_Tuple2(wp.aB, wp.aE);
			} else {
				return A2(
					$elm$core$Result$withDefault,
					_Utils_Tuple2(0, 0),
					A2($author$project$Main$cumulativeGainLossAtDistance, cs.t, tracks.c.bM));
			}
		}();
		var waypointsWithStartFinish = cs.H ? A3($author$project$Main$injectStartFinish, currentFinishDistance, tracks.c.aJ, currentEffectiveWaypoints) : currentEffectiveWaypoints;
		var filteredWaypoints = A2(
			$author$project$Main$trimWaypointCategories,
			state.d,
			A2(
				$author$project$Main$filterWaypoints,
				$author$project$Main$waypointPredicates(state),
				waypointsWithStartFinish));
		var waypointsWithPosition = A2(
			$elm$core$List$sortBy,
			function ($) {
				return $.az;
			},
			function () {
				if (!positionWaypoint.$) {
					var pw = positionWaypoint.a;
					return A2($elm$core$List$cons, pw, filteredWaypoints);
				} else {
					return filteredWaypoints;
				}
			}());
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					$author$project$Main$liveNoPositionWarning(state),
					$author$project$Main$cuesheetSvg(state.w)(state.S)(
					A2(
						$elm$core$Maybe$map,
						function ($) {
							return $.az;
						},
						positionWaypoint))(scrollPosition)(waypointsWithPosition)(cs)(currentFinishDistance)(tracks.c.aJ)(refPointEle)(refWaypoint)
				]));
	});
var $elm$core$Basics$e = _Basics_e;
var $elm$core$Basics$pow = _Basics_pow;
var $author$project$Main$computeIntensity = F2(
	function (tau, trackPoints) {
		if (!trackPoints.b) {
			return _List_Nil;
		} else {
			var first = trackPoints.a;
			var rest = trackPoints.b;
			var _v1 = A3(
				$elm$core$List$foldl,
				F2(
					function (current, _v2) {
						var _v3 = _v2.a;
						var prev = _v3.a;
						var prevIntensity = _v3.b;
						var acc = _v2.b;
						var deltaD = current.az - prev.az;
						var grade = (deltaD > 0) ? ((current.a5 - prev.a5) / deltaD) : 0;
						var decay = A2($elm$core$Basics$pow, $elm$core$Basics$e, (-deltaD) / tau);
						var climbingGrade = A2($elm$core$Basics$max, 0, grade);
						var newIntensity = (decay * prevIntensity) + ((1 - decay) * climbingGrade);
						return _Utils_Tuple2(
							_Utils_Tuple2(current, newIntensity),
							A2(
								$elm$core$List$cons,
								{az: current.az, ap: newIntensity},
								acc));
					}),
				_Utils_Tuple2(
					_Utils_Tuple2(first, 0),
					_List_fromArray(
						[
							{az: first.az, ap: 0}
						])),
				rest);
			var result = _v1.b;
			return $elm$core$List$reverse(result);
		}
	});
var $author$project$Main$niceDistanceInterval = function (range) {
	return (range > 100000) ? 20000 : ((range > 50000) ? 10000 : ((range > 20000) ? 5000 : ((range > 10000) ? 2000 : 1000)));
};
var $author$project$Main$nicePercentInterval = function (range) {
	return (range > 50) ? 25 : ((range > 20) ? 10 : ((range > 10) ? 5 : ((range > 5) ? 2 : 1)));
};
var $elm_community$list_extra$List$Extra$uniqueHelp = F4(
	function (f, existing, remaining, accumulator) {
		uniqueHelp:
		while (true) {
			if (!remaining.b) {
				return $elm$core$List$reverse(accumulator);
			} else {
				var first = remaining.a;
				var rest = remaining.b;
				var computedFirst = f(first);
				if (A2($elm$core$List$member, computedFirst, existing)) {
					var $temp$f = f,
						$temp$existing = existing,
						$temp$remaining = rest,
						$temp$accumulator = accumulator;
					f = $temp$f;
					existing = $temp$existing;
					remaining = $temp$remaining;
					accumulator = $temp$accumulator;
					continue uniqueHelp;
				} else {
					var $temp$f = f,
						$temp$existing = A2($elm$core$List$cons, computedFirst, existing),
						$temp$remaining = rest,
						$temp$accumulator = A2($elm$core$List$cons, first, accumulator);
					f = $temp$f;
					existing = $temp$existing;
					remaining = $temp$remaining;
					accumulator = $temp$accumulator;
					continue uniqueHelp;
				}
			}
		}
	});
var $elm_community$list_extra$List$Extra$uniqueBy = F2(
	function (f, list) {
		return A4($elm_community$list_extra$List$Extra$uniqueHelp, f, _List_Nil, list, _List_Nil);
	});
var $author$project$Main$distanceMarkers = function (cfg) {
	var displayed = function (dist) {
		return A5($author$project$Main$displayedDistanceValue, cfg.aO, cfg.aH, cfg.t, cfg.bw, dist);
	};
	var _v0 = _Utils_Tuple2(
		displayed(cfg.aT),
		displayed(cfg.aT + cfg.bC));
	if ((!_v0.a.$) && (!_v0.b.$)) {
		var vStart = _v0.a.a;
		var vEnd = _v0.b.a;
		var segmentEndValues = cfg.bD ? _List_fromArray(
			[vStart, vEnd]) : _List_Nil;
		var isPercent = $author$project$Main$displayIsPercent(cfg.aO);
		var metresPerDisplayedUnit = isPercent ? (cfg.aH / 100) : 1;
		var toMarker = function (value) {
			return {
				az: ((_Utils_cmp(vStart, vEnd) < 1) ? (value - vStart) : (vStart - value)) * metresPerDisplayedUnit,
				bg: isPercent ? $author$project$Main$formatPercent(value) : A2($author$project$Main$formatKm, cfg.a4, value)
			};
		};
		var _v1 = _Utils_Tuple2(
			A2($elm$core$Basics$min, vStart, vEnd),
			A2($elm$core$Basics$max, vStart, vEnd));
		var vMin = _v1.a;
		var vMax = _v1.b;
		var interval = isPercent ? $author$project$Main$nicePercentInterval(vMax - vMin) : A2(
			$elm$core$Maybe$withDefault,
			$author$project$Main$niceDistanceInterval(vMax - vMin),
			cfg.be);
		var buildValues = F2(
			function (current, acc) {
				buildValues:
				while (true) {
					if (_Utils_cmp(current, vMax) > 0) {
						return $elm$core$List$reverse(acc);
					} else {
						var $temp$current = current + interval,
							$temp$acc = A2($elm$core$List$cons, current, acc);
						current = $temp$current;
						acc = $temp$acc;
						continue buildValues;
					}
				}
			});
		var firstTick = $elm$core$Basics$ceiling(vMin / interval) * interval;
		return A2(
			$elm_community$list_extra$List$Extra$uniqueBy,
			A2(
				$elm$core$Basics$composeR,
				function ($) {
					return $.az;
				},
				$elm$core$Basics$round),
			A2(
				$elm$core$List$map,
				toMarker,
				_Utils_ap(
					A2(buildValues, firstTick, _List_Nil),
					segmentEndValues)));
	} else {
		return _List_Nil;
	}
};
var $author$project$Main$downsample = F2(
	function (maxPoints, list) {
		var len = $elm$core$List$length(list);
		if ((maxPoints < 2) || (_Utils_cmp(len, maxPoints) < 1)) {
			return list;
		} else {
			var stride = (len - 1) / (maxPoints - 1);
			var keepIndices = $elm$core$List$sort(
				A2(
					$elm$core$List$map,
					function (i) {
						return $elm$core$Basics$round(i * stride);
					},
					A2($elm$core$List$range, 0, maxPoints - 1)));
			return function (_v3) {
				var result = _v3.b;
				return $elm$core$List$reverse(result);
			}(
				A3(
					$elm$core$List$foldl,
					F2(
						function (_v0, _v1) {
							var idx = _v0.a;
							var item = _v0.b;
							var remaining = _v1.a;
							var result = _v1.b;
							if (!remaining.b) {
								return _Utils_Tuple2(remaining, result);
							} else {
								var keepIdx = remaining.a;
								var restKeep = remaining.b;
								return _Utils_eq(idx, keepIdx) ? _Utils_Tuple2(
									restKeep,
									A2($elm$core$List$cons, item, result)) : _Utils_Tuple2(remaining, result);
							}
						}),
					_Utils_Tuple2(keepIndices, _List_Nil),
					A2($elm$core$List$indexedMap, $elm$core$Tuple$pair, list)));
		}
	});
var $elm$html$Html$Attributes$id = $elm$html$Html$Attributes$stringProperty('id');
var $elm$core$List$maximum = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(
			A3($elm$core$List$foldl, $elm$core$Basics$max, x, xs));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$List$minimum = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(
			A3($elm$core$List$foldl, $elm$core$Basics$min, x, xs));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$svg$Svg$circle = $elm$svg$Svg$trustedNode('circle');
var $elm$svg$Svg$Attributes$cx = _VirtualDom_attribute('cx');
var $elm$svg$Svg$Attributes$cy = _VirtualDom_attribute('cy');
var $author$project$Main$elevationTicks = F2(
	function (minElev, maxElev) {
		var range = maxElev - minElev;
		var interval = (range > 1000) ? 500 : ((range > 300) ? 100 : ((range > 100) ? 50 : 25));
		var firstTick = $elm$core$Basics$ceiling(minElev / interval) * interval;
		var buildTicks = F2(
			function (current, acc) {
				buildTicks:
				while (true) {
					if (_Utils_cmp(current, maxElev) > 0) {
						return $elm$core$List$reverse(acc);
					} else {
						var $temp$current = current + interval,
							$temp$acc = A2($elm$core$List$cons, current, acc);
						current = $temp$current;
						acc = $temp$acc;
						continue buildTicks;
					}
				}
			});
		return A2(buildTicks, firstTick, _List_Nil);
	});
var $author$project$Main$interpolateWaypointElevation = F2(
	function (trackPoints, distance) {
		interpolateWaypointElevation:
		while (true) {
			if (!trackPoints.b) {
				return 0;
			} else {
				var a = trackPoints.a;
				var others = trackPoints.b;
				if (_Utils_cmp(a.az, distance) > -1) {
					return a.a5;
				} else {
					if (!others.b) {
						return a.a5;
					} else {
						var b = others.a;
						if (_Utils_cmp(b.az, distance) > -1) {
							return a.a5;
						} else {
							var $temp$trackPoints = others,
								$temp$distance = distance;
							trackPoints = $temp$trackPoints;
							distance = $temp$distance;
							continue interpolateWaypointElevation;
						}
					}
				}
			}
		}
	});
var $elm$svg$Svg$Attributes$opacity = _VirtualDom_attribute('opacity');
var $author$project$Main$profileSvgWidth = 500;
var $elm$svg$Svg$Attributes$r = _VirtualDom_attribute('r');
var $elm$svg$Svg$defs = $elm$svg$Svg$trustedNode('defs');
var $elm$svg$Svg$Attributes$id = _VirtualDom_attribute('id');
var $elm$core$Basics$clamp = F3(
	function (low, high, number) {
		return (_Utils_cmp(number, low) < 0) ? low : ((_Utils_cmp(number, high) > 0) ? high : number);
	});
var $author$project$Main$intensityColor = function (t) {
	var clamped = A3($elm$core$Basics$clamp, 0, 1, t);
	var g = $elm$core$Basics$round(
		(clamped < 0.5) ? 255 : (255 * (1 - ((clamped - 0.5) * 2))));
	var r = $elm$core$Basics$round(
		(clamped < 0.5) ? ((255 * clamped) * 2) : 255);
	return 'rgb(' + ($elm$core$String$fromInt(r) + (',' + ($elm$core$String$fromInt(g) + ',0)')));
};
var $elm$svg$Svg$linearGradient = $elm$svg$Svg$trustedNode('linearGradient');
var $elm$svg$Svg$Attributes$offset = _VirtualDom_attribute('offset');
var $elm$svg$Svg$rect = $elm$svg$Svg$trustedNode('rect');
var $elm$svg$Svg$stop = $elm$svg$Svg$trustedNode('stop');
var $elm$svg$Svg$Attributes$stopColor = _VirtualDom_attribute('stop-color');
var $elm$svg$Svg$Attributes$stopOpacity = _VirtualDom_attribute('stop-opacity');
var $author$project$Main$renderIntensityShading = F7(
	function (segmentIndex, svgWidth, maxDistance, trackHeightFloat, intensityPoints, minIntensity, maxIntensity) {
		var intensityRange = maxIntensity - minIntensity;
		var stops = A2(
			$elm$core$List$map,
			function (point) {
				var offsetPct = (maxDistance > 0) ? ($elm$core$String$fromFloat((point.az / maxDistance) * 100) + '%') : '0%';
				var normalized = (intensityRange > 0) ? ((point.ap - minIntensity) / intensityRange) : 0;
				return A2(
					$elm$svg$Svg$stop,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$offset(offsetPct),
							$elm$svg$Svg$Attributes$stopColor(
							$author$project$Main$intensityColor(normalized)),
							$elm$svg$Svg$Attributes$stopOpacity('0.3')
						]),
					_List_Nil);
			},
			intensityPoints);
		var gradientId = 'intensity-gradient-' + $elm$core$String$fromInt(segmentIndex);
		return A2(
			$elm$svg$Svg$g,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$svg$Svg$defs,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$svg$Svg$linearGradient,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$id(gradientId),
									$elm$svg$Svg$Attributes$x1('0'),
									$elm$svg$Svg$Attributes$y1('0'),
									$elm$svg$Svg$Attributes$x2('1'),
									$elm$svg$Svg$Attributes$y2('0')
								]),
							stops)
						])),
					A2(
					$elm$svg$Svg$rect,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x('0'),
							$elm$svg$Svg$Attributes$y('0'),
							$elm$svg$Svg$Attributes$width(
							$elm$core$String$fromFloat(svgWidth)),
							$elm$svg$Svg$Attributes$height(
							$elm$core$String$fromFloat(trackHeightFloat)),
							$elm$svg$Svg$Attributes$fill('url(#' + (gradientId + ')'))
						]),
					_List_Nil)
				]));
	});
var $elm$svg$Svg$Attributes$points = _VirtualDom_attribute('points');
var $elm$svg$Svg$polyline = $elm$svg$Svg$trustedNode('polyline');
var $author$project$Main$resolveElevationProfileSVGLine = F3(
	function (calc, profileData, trackThicknessAttrValue) {
		return A2(
			$elm$svg$Svg$polyline,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$points(
					A2(
						$elm$core$String$join,
						', ',
						A2(
							$elm$core$List$map,
							function (point) {
								return calc.ax(point.az) + (' ' + calc.ay(point.a5));
							},
							profileData))),
					$elm$svg$Svg$Attributes$stroke('grey'),
					$elm$svg$Svg$Attributes$strokeWidth(trackThicknessAttrValue),
					$elm$svg$Svg$Attributes$fill('none')
				]),
			_List_Nil);
	});
var $author$project$Main$XYCalculator = F2(
	function (x, y) {
		return {ax: x, ay: y};
	});
var $author$project$Main$xyCalculator = function (cfg) {
	var svgWidthPerDistanceUnit = cfg.bI / cfg.bj;
	var elevationRange = cfg.bk - cfg.aN;
	var normaliseElevation = function (elevation) {
		return (elevation - cfg.aN) / elevationRange;
	};
	return A2(
		$author$project$Main$XYCalculator,
		function (distance) {
			return $elm$core$String$fromFloat(distance * svgWidthPerDistanceUnit);
		},
		function (elevation) {
			return $elm$core$String$fromFloat(
				cfg.aW - (cfg.aW * normaliseElevation(elevation)));
		});
};
var $author$project$Main$profile = function (segmentIndex) {
	return function (track) {
		return function (fullTrackpoints) {
			return function (maxDistance) {
				return function (minElevation) {
					return function (maxElevation) {
						return function (fontSize) {
							return function (trackHeight) {
								return function (trackThickness) {
									return function (labelHeightGain) {
										return function (offRouteThreshold) {
											return function (maybePosition) {
												return function (intensityPoints) {
													return function (minIntensity) {
														return function (maxIntensity) {
															return function (markers) {
																var waypointTextHeight = function (len) {
																	return A2(
																		$elm$core$Basics$max,
																		100,
																		$elm$core$Basics$round(((len * 0.6) * fontSize) * labelHeightGain));
																}(
																	A2(
																		$elm$core$Maybe$withDefault,
																		0,
																		$elm$core$List$maximum(
																			A2(
																				$elm$core$List$map,
																				function (w) {
																					return $elm$core$String$length(w.bn);
																				},
																				track.bP))));
																var markerLabelHeight = $elm$core$List$isEmpty(markers) ? 0 : 14;
																var svgHeight = (trackHeight + markerLabelHeight) + waypointTextHeight;
																var calc = $author$project$Main$xyCalculator(
																	{bj: maxDistance, bk: maxElevation, aN: minElevation, aW: trackHeight, bI: $author$project$Main$profileSvgWidth});
																return A2(
																	$elm$html$Html$div,
																	_List_fromArray(
																		[
																			A2($elm$html$Html$Attributes$style, 'margin-top', '16px'),
																			A2($elm$html$Html$Attributes$style, 'padding', '0 8px')
																		]),
																	_List_fromArray(
																		[
																			function () {
																			var _v0 = track.aJ;
																			var gain = _v0.a;
																			var loss = _v0.b;
																			return A2(
																				$elm$html$Html$div,
																				_List_fromArray(
																					[
																						A2($elm$html$Html$Attributes$style, 'text-align', 'center'),
																						A2($elm$html$Html$Attributes$style, 'font-size', '1em'),
																						A2($elm$html$Html$Attributes$style, 'padding', '4px 0')
																					]),
																				_List_fromArray(
																					[
																						$elm$html$Html$text(
																						A2($author$project$Main$formatKm, 1, maxDistance) + (' ' + A2($author$project$Main$formatEleGainLoss, gain, loss)))
																					]));
																		}(),
																			A2(
																			$elm$svg$Svg$svg,
																			_List_fromArray(
																				[
																					$elm$svg$Svg$Attributes$viewBox(
																					'-50 -5 ' + ($elm$core$String$fromInt($author$project$Main$profileSvgWidth + 55) + (' ' + $elm$core$String$fromInt(svgHeight + 10))))
																				]),
																			_List_fromArray(
																				[
																					$elm$core$List$isEmpty(intensityPoints) ? A2($elm$svg$Svg$g, _List_Nil, _List_Nil) : A7($author$project$Main$renderIntensityShading, segmentIndex, $author$project$Main$profileSvgWidth, maxDistance, trackHeight, intensityPoints, minIntensity, maxIntensity),
																					A2(
																					$elm$svg$Svg$g,
																					_List_Nil,
																					A2(
																						$elm$core$List$concatMap,
																						function (tickElev) {
																							var y = calc.ay(tickElev);
																							return _List_fromArray(
																								[
																									A2(
																									$elm$svg$Svg$line,
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$x1('-5'),
																											$elm$svg$Svg$Attributes$y1(y),
																											$elm$svg$Svg$Attributes$x2('0'),
																											$elm$svg$Svg$Attributes$y2(y),
																											$elm$svg$Svg$Attributes$stroke('grey'),
																											$elm$svg$Svg$Attributes$strokeWidth('1')
																										]),
																									_List_Nil),
																									A2(
																									$elm$svg$Svg$text_,
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$x('-8'),
																											$elm$svg$Svg$Attributes$y(y),
																											$elm$svg$Svg$Attributes$textAnchor('end'),
																											$elm$svg$Svg$Attributes$dominantBaseline('central'),
																											$elm$svg$Svg$Attributes$fontSize('10'),
																											$elm$svg$Svg$Attributes$fill('grey')
																										]),
																									_List_fromArray(
																										[
																											$elm$svg$Svg$text(
																											$elm$core$String$fromInt(
																												$elm$core$Basics$round(tickElev)))
																										]))
																								]);
																						},
																						A2($author$project$Main$elevationTicks, minElevation, maxElevation))),
																					A2(
																					$elm$svg$Svg$g,
																					_List_Nil,
																					A2(
																						$elm$core$List$concatMap,
																						function (marker) {
																							var x = calc.ax(marker.az);
																							return _List_fromArray(
																								[
																									A2(
																									$elm$svg$Svg$line,
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$x1(x),
																											$elm$svg$Svg$Attributes$y1(
																											$elm$core$String$fromInt(trackHeight - 4)),
																											$elm$svg$Svg$Attributes$x2(x),
																											$elm$svg$Svg$Attributes$y2(
																											$elm$core$String$fromInt(trackHeight + 4)),
																											$elm$svg$Svg$Attributes$stroke('grey'),
																											$elm$svg$Svg$Attributes$strokeWidth('1')
																										]),
																									_List_Nil),
																									A2(
																									$elm$svg$Svg$text_,
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$x(x),
																											$elm$svg$Svg$Attributes$y(
																											$elm$core$String$fromInt((trackHeight + markerLabelHeight) - 3)),
																											$elm$svg$Svg$Attributes$textAnchor('middle'),
																											$elm$svg$Svg$Attributes$fontSize('10'),
																											$elm$svg$Svg$Attributes$fill('grey')
																										]),
																									_List_fromArray(
																										[
																											$elm$svg$Svg$text(marker.bg)
																										]))
																								]);
																						},
																						markers)),
																					A2(
																					$elm$svg$Svg$g,
																					_List_Nil,
																					function () {
																						var svgBottom = $elm$core$String$fromInt(svgHeight);
																						var paddedWaypointTextY = $elm$core$String$fromInt((trackHeight + 5) + markerLabelHeight);
																						return A2(
																							$elm$core$List$concatMap,
																							function (waypoint) {
																								var y = calc.ay(
																									A2($author$project$Main$interpolateWaypointElevation, fullTrackpoints, waypoint.az) - 5);
																								var x = calc.ax(waypoint.az);
																								var isOffRoute = _Utils_cmp(waypoint.bo, offRouteThreshold) > 0;
																								var strokeColor = isOffRoute ? $author$project$Main$offRouteColour : 'lightgray';
																								return _List_fromArray(
																									[
																										A2(
																										$elm$svg$Svg$line,
																										_List_fromArray(
																											[
																												$elm$svg$Svg$Attributes$x1(x),
																												$elm$svg$Svg$Attributes$y1(svgBottom),
																												$elm$svg$Svg$Attributes$x2(x),
																												$elm$svg$Svg$Attributes$y2(y),
																												$elm$svg$Svg$Attributes$stroke(strokeColor),
																												$elm$svg$Svg$Attributes$strokeWidth('1')
																											]),
																										_List_Nil),
																										A2(
																										$elm$svg$Svg$text_,
																										_Utils_ap(
																											_List_fromArray(
																												[
																													$elm$svg$Svg$Attributes$fontSize(
																													$elm$core$String$fromFloat(fontSize)),
																													$elm$svg$Svg$Attributes$dominantBaseline('text-top'),
																													$elm$svg$Svg$Attributes$transform('translate(' + (x + (', ' + (paddedWaypointTextY + ') rotate(90)'))))
																												]),
																											isOffRoute ? _List_fromArray(
																												[
																													$elm$svg$Svg$Attributes$fill('orange')
																												]) : _List_Nil),
																										_List_fromArray(
																											[
																												$elm$svg$Svg$text(waypoint.bn)
																											]))
																									]);
																							},
																							track.bP);
																					}()),
																					A3(
																					$author$project$Main$resolveElevationProfileSVGLine,
																					calc,
																					track.bM,
																					$elm$core$String$fromFloat(trackThickness)),
																					function () {
																					if (!maybePosition.$) {
																						var posDistance = maybePosition.a;
																						var yPos = calc.ay(
																							A2($author$project$Main$interpolateWaypointElevation, fullTrackpoints, posDistance));
																						var xPos = calc.ax(posDistance);
																						return A2(
																							$elm$svg$Svg$g,
																							_List_Nil,
																							_List_fromArray(
																								[
																									A2(
																									$elm$svg$Svg$line,
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$x1(xPos),
																											$elm$svg$Svg$Attributes$y1('0'),
																											$elm$svg$Svg$Attributes$x2(xPos),
																											$elm$svg$Svg$Attributes$y2(
																											$elm$core$String$fromInt(trackHeight)),
																											$elm$svg$Svg$Attributes$stroke('dodgerblue'),
																											$elm$svg$Svg$Attributes$strokeWidth('2'),
																											$elm$svg$Svg$Attributes$opacity('0.7')
																										]),
																									_List_Nil),
																									A2(
																									$elm$svg$Svg$circle,
																									_List_fromArray(
																										[
																											$elm$svg$Svg$Attributes$cx(xPos),
																											$elm$svg$Svg$Attributes$cy(yPos),
																											$elm$svg$Svg$Attributes$r('3.5'),
																											$elm$svg$Svg$Attributes$fill('dodgerblue')
																										]),
																									_List_Nil)
																								]));
																					} else {
																						return A2($elm$svg$Svg$g, _List_Nil, _List_Nil);
																					}
																				}(),
																					A2(
																					$elm$svg$Svg$g,
																					_List_Nil,
																					A2(
																						$elm$core$List$map,
																						function (_v2) {
																							var _v3 = _v2.a;
																							var y1 = _v3.a;
																							var x1 = _v3.b;
																							var _v4 = _v2.b;
																							var y2 = _v4.a;
																							var x2 = _v4.b;
																							return A2(
																								$elm$svg$Svg$line,
																								_List_fromArray(
																									[
																										$elm$svg$Svg$Attributes$x1(
																										$elm$core$String$fromInt(x1)),
																										$elm$svg$Svg$Attributes$y1(
																										$elm$core$String$fromInt(y1)),
																										$elm$svg$Svg$Attributes$x2(
																										$elm$core$String$fromInt(x2)),
																										$elm$svg$Svg$Attributes$y2(
																										$elm$core$String$fromInt(y2)),
																										$elm$svg$Svg$Attributes$stroke('grey'),
																										$elm$svg$Svg$Attributes$strokeWidth('1')
																									]),
																								_List_Nil);
																						},
																						_List_fromArray(
																							[
																								_Utils_Tuple2(
																								_Utils_Tuple2(0, 0),
																								_Utils_Tuple2(trackHeight, 0)),
																								_Utils_Tuple2(
																								_Utils_Tuple2(0, 0),
																								_Utils_Tuple2(0, $author$project$Main$profileSvgWidth)),
																								_Utils_Tuple2(
																								_Utils_Tuple2(trackHeight, $author$project$Main$profileSvgWidth),
																								_Utils_Tuple2(trackHeight, 0)),
																								_Utils_Tuple2(
																								_Utils_Tuple2(trackHeight, $author$project$Main$profileSvgWidth),
																								_Utils_Tuple2(0, $author$project$Main$profileSvgWidth))
																							])))
																				]))
																		]));
															};
														};
													};
												};
											};
										};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $author$project$Main$profileContainerId = 'profile-container';
var $author$project$Main$viewElevationProfileTab = F2(
	function (state, tracks) {
		var trackMinElevation = A2(
			$elm$core$Maybe$withDefault,
			1,
			$elm$core$List$minimum(
				A2(
					$elm$core$List$map,
					function ($) {
						return $.a5;
					},
					tracks.c.bM)));
		var trackMaxElevation = A2(
			$elm$core$Maybe$withDefault,
			1,
			$elm$core$List$maximum(
				A2(
					$elm$core$List$map,
					function ($) {
						return $.a5;
					},
					tracks.c.bM)));
		var ep = state.a;
		var fullIntensity = ep.G ? A2($author$project$Main$computeIntensity, ep.O, tracks.c.bM) : _List_Nil;
		var currentFinishDistance = $author$project$Main$lastTrackpointDistance(tracks.c.bM);
		var currentEffectiveWaypoints = $author$project$Main$effectiveWaypoints(tracks.c.f);
		var cs = state.e;
		var refWaypoint = function () {
			var _v5 = cs.h;
			switch (_v5.$) {
				case 3:
					var idx = _v5.a;
					return A2($elm_community$list_extra$List$Extra$getAt, idx, currentEffectiveWaypoints);
				case 4:
					var idx = _v5.a;
					return A2($elm_community$list_extra$List$Extra$getAt, idx, currentEffectiveWaypoints);
				default:
					return $elm$core$Maybe$Nothing;
			}
		}();
		var _v0 = A3(
			$elm$core$List$foldl,
			F2(
				function (pt, _v1) {
					var mn = _v1.a;
					var mx = _v1.b;
					return _Utils_Tuple2(
						A2($elm$core$Basics$min, mn, pt.ap),
						A2($elm$core$Basics$max, mx, pt.ap));
				}),
			_Utils_Tuple2(1 / 0, -(1 / 0)),
			fullIntensity);
		var trackMinIntensity = _v0.a;
		var trackMaxIntensity = _v0.b;
		var _v2 = state.I;
		if (_v2.$ === 1) {
			return $elm$html$Html$text('');
		} else {
			var splitResult = _v2.a;
			var downsampleWidth = A2($elm$core$Maybe$withDefault, $author$project$Main$profileSvgWidth, state.ai);
			var profileViews = A2(
				$elm$core$List$indexedMap,
				F2(
					function (segIndex, _v3) {
						var _v4 = _v3.a;
						var segStart = _v4.a;
						var segEnd = _v4.b;
						var seg = _v3.b;
						var segPosition = A2(
							$elm$core$Maybe$andThen,
							function (p) {
								return ((_Utils_cmp(p, segStart) > -1) && (_Utils_cmp(p, segEnd) < 1)) ? $elm$core$Maybe$Just(p - segStart) : $elm$core$Maybe$Nothing;
							},
							state.cg);
						var segMaxDistance = A2(
							$elm$core$Maybe$withDefault,
							segEnd - segStart,
							A2(
								$elm$core$Maybe$map,
								function ($) {
									return $.az;
								},
								$elm$core$List$head(
									$elm$core$List$reverse(seg.bM))));
						var segIntensity = A2(
							$author$project$Main$downsample,
							downsampleWidth,
							A2(
								$elm$core$List$map,
								function (pt) {
									return _Utils_update(
										pt,
										{az: pt.az - segStart});
								},
								A2(
									$elm$core$List$filter,
									function (pt) {
										return (_Utils_cmp(pt.az, segStart) > -1) && (_Utils_cmp(pt.az, segEnd) < 1);
									},
									fullIntensity)));
						var markers = $author$project$Main$distanceMarkers(
							{a4: cs.A, aH: currentFinishDistance, be: ep.M, aO: cs.h, bw: refWaypoint, t: cs.t, bC: segMaxDistance, aT: segStart, bD: ep.N});
						var downsampledSeg = _Utils_update(
							seg,
							{
								bM: A2($author$project$Main$downsample, downsampleWidth, seg.bM)
							});
						return $author$project$Main$profile(segIndex)(downsampledSeg)(seg.bM)(segMaxDistance)(trackMinElevation)(trackMaxElevation)(ep.W)(ep.ac)(ep.ad)(ep.X)(state.w)(segPosition)(segIntensity)(trackMinIntensity)(trackMaxIntensity)(markers);
					}),
				A3($elm$core$List$map2, $elm$core$Tuple$pair, splitResult.bW, splitResult.ck));
			return A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						$author$project$Main$liveNoPositionWarning(state),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$id($author$project$Main$profileContainerId)
							]),
						profileViews)
					]));
		}
	});
var $author$project$Main$viewErrorPanel = function (error) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('error_panel')
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(error)
			]));
};
var $author$project$Main$OpenFileBrowser = {$: 3};
var $elm$html$Html$br = _VirtualDom_node('br');
var $elm$html$Html$h2 = _VirtualDom_node('h2');
var $elm$html$Html$h3 = _VirtualDom_node('h3');
var $elm$html$Html$li = _VirtualDom_node('li');
var $elm$html$Html$ul = _VirtualDom_node('ul');
var $elm$html$Html$button = _VirtualDom_node('button');
var $elm$virtual_dom$VirtualDom$Normal = function (a) {
	return {$: 0, a: a};
};
var $elm$virtual_dom$VirtualDom$on = _VirtualDom_on;
var $elm$html$Html$Events$on = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$Normal(decoder));
	});
var $elm$html$Html$Events$onClick = function (msg) {
	return A2(
		$elm$html$Html$Events$on,
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $author$project$Main$viewButton = F3(
	function (attrs, text, onClickMsg) {
		return A2(
			$elm$html$Html$button,
			_Utils_ap(
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(onClickMsg),
						$elm$html$Html$Attributes$class('button-4'),
						A2($elm$html$Html$Attributes$style, 'max-width', '20em')
					]),
				attrs),
			_List_fromArray(
				[
					$elm$html$Html$text(text)
				]));
	});
var $author$project$Main$viewLandingPage = A2(
	$elm$html$Html$div,
	_List_fromArray(
		[
			$elm$html$Html$Attributes$class('flex-container'),
			$elm$html$Html$Attributes$class('flex-center'),
			$elm$html$Html$Attributes$class('column')
		]),
	_List_fromArray(
		[
			A2(
			$elm$html$Html$h2,
			_List_Nil,
			_List_fromArray(
				[
					$elm$html$Html$text('Route tools')
				])),
			A2($elm$html$Html$br, _List_Nil, _List_Nil),
			A3($author$project$Main$viewButton, _List_Nil, 'Upload GPX', $author$project$Main$OpenFileBrowser),
			A2($elm$html$Html$br, _List_Nil, _List_Nil),
			A2(
			$elm$html$Html$h3,
			_List_Nil,
			_List_fromArray(
				[
					$elm$html$Html$text('Features')
				])),
			A2($elm$html$Html$br, _List_Nil, _List_Nil),
			A2(
			$elm$html$Html$ul,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$li,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Elevation profile visualization')
						])),
					A2(
					$elm$html$Html$li,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Cuesheet with customizable distance display')
						])),
					A2(
					$elm$html$Html$li,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('GPS location tracking')
						])),
					A2(
					$elm$html$Html$li,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Waypoint category filtering')
						])),
					A2(
					$elm$html$Html$li,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Inline waypoint editing')
						])),
					A2(
					$elm$html$Html$li,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('Multi-track GPX support')
						]))
				]))
		]));
var $author$project$Main$DownloadSplitsGpx = {$: 53};
var $author$project$Main$SetViewMode = function (a) {
	return {$: 33, a: a};
};
var $author$project$Main$ShowOptions = function (a) {
	return {$: 2, a: a};
};
var $author$project$Main$UpdateLiveLookahead = function (a) {
	return {$: 38, a: a};
};
var $author$project$Main$UpdateLiveLookbehind = function (a) {
	return {$: 39, a: a};
};
var $elm$html$Html$hr = _VirtualDom_node('hr');
var $elm$html$Html$input = _VirtualDom_node('input');
var $elm$html$Html$Attributes$max = $elm$html$Html$Attributes$stringProperty('max');
var $elm$html$Html$Attributes$min = $elm$html$Html$Attributes$stringProperty('min');
var $elm$html$Html$Events$alwaysStop = function (x) {
	return _Utils_Tuple2(x, true);
};
var $elm$virtual_dom$VirtualDom$MayStopPropagation = function (a) {
	return {$: 1, a: a};
};
var $elm$html$Html$Events$stopPropagationOn = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$MayStopPropagation(decoder));
	});
var $elm$json$Json$Decode$at = F2(
	function (fields, decoder) {
		return A3($elm$core$List$foldr, $elm$json$Json$Decode$field, decoder, fields);
	});
var $elm$html$Html$Events$targetValue = A2(
	$elm$json$Json$Decode$at,
	_List_fromArray(
		['target', 'value']),
	$elm$json$Json$Decode$string);
var $elm$html$Html$Events$onInput = function (tagger) {
	return A2(
		$elm$html$Html$Events$stopPropagationOn,
		'input',
		A2(
			$elm$json$Json$Decode$map,
			$elm$html$Html$Events$alwaysStop,
			A2($elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetValue)));
};
var $elm$html$Html$option = _VirtualDom_node('option');
var $elm$html$Html$legend = _VirtualDom_node('legend');
var $author$project$Main$optionGroup = F2(
	function (title, elements) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('flex-container'),
					$elm$html$Html$Attributes$class('column')
				]),
			A2(
				$elm$core$List$cons,
				A2(
					$elm$html$Html$legend,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(title)
						])),
				elements));
	});
var $elm$html$Html$select = _VirtualDom_node('select');
var $elm$html$Html$Attributes$boolProperty = F2(
	function (key, bool) {
		return A2(
			_VirtualDom_property,
			key,
			$elm$json$Json$Encode$bool(bool));
	});
var $elm$html$Html$Attributes$selected = $elm$html$Html$Attributes$boolProperty('selected');
var $elm$html$Html$Attributes$step = function (n) {
	return A2($elm$html$Html$Attributes$stringProperty, 'step', n);
};
var $elm$core$String$toFloat = _String_toFloat;
var $elm$html$Html$Attributes$type_ = $elm$html$Html$Attributes$stringProperty('type');
var $elm$html$Html$Attributes$value = $elm$html$Html$Attributes$stringProperty('value');
var $author$project$Main$CategoryEnabled = F2(
	function (a, b) {
		return {$: 16, a: a, b: b};
	});
var $author$project$Main$SetAllCategoriesEnabled = function (a) {
	return {$: 18, a: a};
};
var $author$project$Main$UpdateCategoryFilterEnabled = function (a) {
	return {$: 17, a: a};
};
var $author$project$Main$UpdateOffRouteThreshold = function (a) {
	return {$: 50, a: a};
};
var $author$project$Main$UpdateShowOffRouteDistance = function (a) {
	return {$: 48, a: a};
};
var $author$project$Main$UpdateShowOffRouteWaypoints = function (a) {
	return {$: 51, a: a};
};
var $elm$html$Html$Attributes$checked = $elm$html$Html$Attributes$boolProperty('checked');
var $elm$html$Html$label = _VirtualDom_node('label');
var $author$project$Main$checkbox = F3(
	function (checked, msg, label) {
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('checkbox'),
							$elm$html$Html$Events$onClick(msg),
							$elm$html$Html$Attributes$checked(checked)
						]),
					_List_Nil),
					A2(
					$elm$html$Html$label,
					_List_fromArray(
						[
							$elm$html$Html$Events$onClick(msg)
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label)
						]))
				]));
	});
var $elm$html$Html$fieldset = _VirtualDom_node('fieldset');
var $author$project$Main$viewCategoryFilterOptions = function (state) {
	return _List_fromArray(
		[
			A2(
			$author$project$Main$optionGroup,
			'Waypoint categories',
			A2(
				$elm$core$List$cons,
				A2(
					$elm$html$Html$select,
					_List_fromArray(
						[
							$elm$html$Html$Events$onInput(
							function (val) {
								if (val === 'all') {
									return $author$project$Main$UpdateCategoryFilterEnabled(false);
								} else {
									return $author$project$Main$UpdateCategoryFilterEnabled(true);
								}
							})
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$option,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$value('all'),
									$elm$html$Html$Attributes$selected(!state.z)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('all')
								])),
							A2(
							$elm$html$Html$option,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$value('filtered'),
									$elm$html$Html$Attributes$selected(state.z)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('filtered')
								]))
						])),
				state.z ? _List_fromArray(
					[
						A2(
						$elm$html$Html$fieldset,
						_List_Nil,
						_Utils_ap(
							A2(
								$elm$core$List$map,
								function (_v1) {
									var cat = _v1.a;
									var included = _v1.b;
									return A3(
										$author$project$Main$checkbox,
										included,
										A2($author$project$Main$CategoryEnabled, cat, !included),
										(!_Utils_eq(cat, $author$project$Main$unknownCategory)) ? cat : 'unknown');
								},
								$elm$core$Dict$toList(state.d)),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Events$onClick(
											$author$project$Main$SetAllCategoriesEnabled(true))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('All')
										])),
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Events$onClick(
											$author$project$Main$SetAllCategoriesEnabled(false))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('None')
										]))
								])))
					]) : _List_Nil)),
			A2(
			$author$project$Main$optionGroup,
			'Off-route threshold: ' + ($elm$core$String$fromInt(
				$elm$core$Basics$round(state.w)) + 'm'),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('0'),
							$elm$html$Html$Attributes$max('1000'),
							$elm$html$Html$Attributes$step('10'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromFloat(state.w)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toFloat,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault(100),
									$author$project$Main$UpdateOffRouteThreshold)))
						]),
					_List_Nil),
					A3(
					$author$project$Main$checkbox,
					state.T,
					$author$project$Main$UpdateShowOffRouteWaypoints(!state.T),
					'Show off-route waypoints'),
					A3(
					$author$project$Main$checkbox,
					state.S,
					$author$project$Main$UpdateShowOffRouteDistance(!state.S),
					'Show off-route distance')
				])),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil)
		]);
};
var $author$project$Main$UpdateDistanceDetail = function (a) {
	return {$: 46, a: a};
};
var $author$project$Main$UpdateItemSpacing = function (a) {
	return {$: 45, a: a};
};
var $author$project$Main$UpdateShowStartFinish = function (a) {
	return {$: 47, a: a};
};
var $abadi199$elm_input_extra$Dropdown$Item = F3(
	function (value, text, enabled) {
		return {a6: enabled, bK: text, aY: value};
	});
var $abadi199$elm_input_extra$Dropdown$Options = F3(
	function (items, emptyItem, onChange) {
		return {aA: emptyItem, aD: items, aR: onChange};
	});
var $author$project$Main$UpdateReferencePoint = function (a) {
	return {$: 44, a: a};
};
var $author$project$Main$UpdateTotalDistanceDisplay = function (a) {
	return {$: 43, a: a};
};
var $elm$html$Html$Attributes$disabled = $elm$html$Html$Attributes$boolProperty('disabled');
var $abadi199$elm_input_extra$Dropdown$onChange = F2(
	function (emptyItem, tagger) {
		var textToMaybe = function (string) {
			return A2(
				$elm$core$Maybe$withDefault,
				false,
				A2(
					$elm$core$Maybe$map,
					A2(
						$elm$core$Basics$composeR,
						function ($) {
							return $.aY;
						},
						$elm$core$Basics$eq(string)),
					emptyItem)) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(string);
		};
		return A2(
			$elm$html$Html$Events$on,
			'change',
			A2(
				$elm$json$Json$Decode$map,
				A2($elm$core$Basics$composeR, textToMaybe, tagger),
				$elm$html$Html$Events$targetValue));
	});
var $abadi199$elm_input_extra$Dropdown$dropdown = F3(
	function (options, attributes, currentValue) {
		var itemsWithEmptyItems = function () {
			var _v1 = options.aA;
			if (!_v1.$) {
				var emptyItem = _v1.a;
				return A2($elm$core$List$cons, emptyItem, options.aD);
			} else {
				return options.aD;
			}
		}();
		var isSelected = function (value) {
			return A2(
				$elm$core$Maybe$withDefault,
				false,
				A2(
					$elm$core$Maybe$map,
					$elm$core$Basics$eq(value),
					currentValue));
		};
		var toOption = function (_v0) {
			var value = _v0.aY;
			var text = _v0.bK;
			var enabled = _v0.a6;
			return A2(
				$elm$html$Html$option,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$value(value),
						$elm$html$Html$Attributes$selected(
						isSelected(value)),
						$elm$html$Html$Attributes$disabled(!enabled)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(text)
					]));
		};
		return A2(
			$elm$html$Html$select,
			_Utils_ap(
				attributes,
				_List_fromArray(
					[
						A2($abadi199$elm_input_extra$Dropdown$onChange, options.aA, options.aR)
					])),
			A2($elm$core$List$map, toOption, itemsWithEmptyItems));
	});
var $author$project$Main$formatTotalDistanceDisplayLabel = function (v) {
	switch (v.$) {
		case 3:
			return 'to waypoint';
		case 4:
			return 'from waypoint';
		default:
			var other = v;
			return $author$project$Main$formatTotalDistanceDisplay(other);
	}
};
var $author$project$Main$UpdateSelectedWaypoint = function (a) {
	return {$: 49, a: a};
};
var $author$project$Main$viewWaypointSelector = F2(
	function (indexed, selectedIdx) {
		return A3(
			$abadi199$elm_input_extra$Dropdown$dropdown,
			A3(
				$abadi199$elm_input_extra$Dropdown$Options,
				A2(
					$elm$core$List$map,
					function (_v0) {
						var idx = _v0.a;
						var wp = _v0.b;
						var label = wp.bn + (' (km ' + (A2($author$project$Main$formatKm, 1, wp.az) + ')'));
						return A3(
							$abadi199$elm_input_extra$Dropdown$Item,
							$elm$core$String$fromInt(idx),
							label,
							true);
					},
					indexed),
				$elm$core$Maybe$Nothing,
				function (maybeStr) {
					var _v1 = A2($elm$core$Maybe$andThen, $elm$core$String$toInt, maybeStr);
					if (!_v1.$) {
						var idx = _v1.a;
						return $author$project$Main$UpdateSelectedWaypoint(idx);
					} else {
						return $author$project$Main$Ignore;
					}
				}),
			_List_Nil,
			$elm$core$Maybe$Just(
				$elm$core$String$fromInt(selectedIdx)));
	});
var $author$project$Main$viewTotalDistanceOptions = function (state) {
	var maybeTracks = $author$project$Main$maybeFromloadableResource(state.b);
	var maxDistance = A2(
		$elm$core$Maybe$map,
		function (ts) {
			return $author$project$Main$lastTrackpointDistance(ts.c.bM);
		},
		maybeTracks);
	var cs = state.e;
	var filteredWps = A2(
		$elm$core$Maybe$withDefault,
		_List_Nil,
		A2(
			$elm$core$Maybe$map,
			function (ts) {
				var currentEffective = $author$project$Main$effectiveWaypoints(ts.c.f);
				return A2(
					$author$project$Main$trimWaypointCategories,
					state.d,
					A2(
						$author$project$Main$filterWaypoints,
						$author$project$Main$waypointPredicates(state),
						cs.H ? A3(
							$author$project$Main$injectStartFinish,
							$author$project$Main$lastTrackpointDistance(ts.c.bM),
							ts.c.aJ,
							currentEffective) : currentEffective));
			},
			maybeTracks));
	var indexedFiltered = A2(
		$elm$core$Maybe$withDefault,
		_List_Nil,
		A2(
			$elm$core$Maybe$map,
			A2(
				$elm$core$Basics$composeR,
				function ($) {
					return $.c;
				},
				A2(
					$elm$core$Basics$composeR,
					function ($) {
						return $.f;
					},
					A2(
						$elm$core$Basics$composeR,
						$author$project$Main$effectiveWaypoints,
						function (waypoints) {
							return A2($author$project$Main$indexedFilteredWaypoints, waypoints, filteredWps);
						}))),
			maybeTracks));
	var defaultWaypointIdx = A2(
		$elm$core$Maybe$withDefault,
		0,
		A2(
			$elm$core$Maybe$map,
			$elm$core$Tuple$first,
			$elm$core$List$head(indexedFiltered)));
	var parseModeDropdown = function (maybeStr) {
		_v1$2:
		while (true) {
			if (!maybeStr.$) {
				switch (maybeStr.a) {
					case 'to waypoint':
						return $author$project$Main$UpdateTotalDistanceDisplay(
							$elm$core$Maybe$Just(
								$author$project$Main$ToWaypoint(defaultWaypointIdx)));
					case 'from waypoint':
						return $author$project$Main$UpdateTotalDistanceDisplay(
							$elm$core$Maybe$Just(
								$author$project$Main$FromWaypoint(defaultWaypointIdx)));
					default:
						break _v1$2;
				}
			} else {
				break _v1$2;
			}
		}
		return $author$project$Main$UpdateTotalDistanceDisplay(
			A2(
				$elm$core$Maybe$withDefault,
				$elm$core$Maybe$Nothing,
				A2($elm$core$Maybe$map, $author$project$Main$parseTotalDistanceDisplay, maybeStr)));
	};
	return A2(
		$author$project$Main$optionGroup,
		'Total distance',
		_Utils_ap(
			_List_fromArray(
				[
					A3(
					$abadi199$elm_input_extra$Dropdown$dropdown,
					A3(
						$abadi199$elm_input_extra$Dropdown$Options,
						_List_fromArray(
							[
								A3(
								$abadi199$elm_input_extra$Dropdown$Item,
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$FromZero),
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$FromZero),
								true),
								A3(
								$abadi199$elm_input_extra$Dropdown$Item,
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$ToFinish),
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$ToFinish),
								true),
								A3(
								$abadi199$elm_input_extra$Dropdown$Item,
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$ToPoint),
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$ToPoint),
								true),
								A3($abadi199$elm_input_extra$Dropdown$Item, 'to waypoint', 'to waypoint', true),
								A3($abadi199$elm_input_extra$Dropdown$Item, 'from waypoint', 'from waypoint', true),
								A3(
								$abadi199$elm_input_extra$Dropdown$Item,
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$PercentProgress),
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$PercentProgress),
								true),
								A3(
								$abadi199$elm_input_extra$Dropdown$Item,
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$PercentRemaining),
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$PercentRemaining),
								true),
								A3(
								$abadi199$elm_input_extra$Dropdown$Item,
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$None),
								$author$project$Main$formatTotalDistanceDisplay($author$project$Main$None),
								true)
							]),
						$elm$core$Maybe$Nothing,
						parseModeDropdown),
					_List_Nil,
					$elm$core$Maybe$Just(
						$author$project$Main$formatTotalDistanceDisplayLabel(cs.h)))
				]),
			function () {
				var _v0 = cs.h;
				switch (_v0.$) {
					case 2:
						return _List_fromArray(
							[
								A2(
								$elm$html$Html$p,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$input,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$type_('number'),
												$elm$html$Html$Attributes$min('0'),
												A2(
												$elm$core$Maybe$withDefault,
												$elm$html$Html$Attributes$disabled(true),
												A2(
													$elm$core$Maybe$map,
													A2($elm$core$Basics$composeR, $elm$core$String$fromFloat, $elm$html$Html$Attributes$max),
													maxDistance)),
												$elm$html$Html$Attributes$value(
												$elm$core$String$fromFloat(cs.t)),
												$elm$html$Html$Events$onInput(
												A2(
													$elm$core$Basics$composeR,
													$elm$core$String$toFloat,
													A2(
														$elm$core$Basics$composeR,
														$elm$core$Maybe$withDefault(1000),
														$author$project$Main$UpdateReferencePoint)))
											]),
										_List_Nil)
									]))
							]);
					case 3:
						var selectedIdx = _v0.a;
						return _List_fromArray(
							[
								A2($author$project$Main$viewWaypointSelector, indexedFiltered, selectedIdx)
							]);
					case 4:
						var selectedIdx = _v0.a;
						return _List_fromArray(
							[
								A2($author$project$Main$viewWaypointSelector, indexedFiltered, selectedIdx)
							]);
					default:
						return _List_Nil;
				}
			}()));
};
var $author$project$Main$viewCuesheetOptionsPanel = function (state) {
	var cs = state.e;
	return _List_fromArray(
		[
			A2(
			$author$project$Main$optionGroup,
			'Start/Finish',
			_List_fromArray(
				[
					A3(
					$author$project$Main$checkbox,
					cs.H,
					$author$project$Main$UpdateShowStartFinish(!cs.H),
					'Show start/finish')
				])),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil),
			$author$project$Main$viewTotalDistanceOptions(state),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil),
			A2(
			$author$project$Main$optionGroup,
			'Spacing',
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('1'),
							$elm$html$Html$Attributes$max('50'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromInt(cs.m)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toInt,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault($author$project$Main$defaultSpacing),
									$author$project$Main$UpdateItemSpacing)))
						]),
					_List_Nil)
				])),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil),
			A2(
			$author$project$Main$optionGroup,
			'Distance detail',
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('0'),
							$elm$html$Html$Attributes$max('3'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromInt(cs.A)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toInt,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault($author$project$Main$defaultDistanceDetail),
									$author$project$Main$UpdateDistanceDetail)))
						]),
					_List_Nil)
				])),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil)
		]);
};
var $author$project$Main$AddSplitWaypoint = {$: 35};
var $author$project$Main$RemoveSplitWaypoint = function (a) {
	return {$: 37, a: a};
};
var $author$project$Main$SetSplitMode = function (a) {
	return {$: 34, a: a};
};
var $author$project$Main$ShowIntensity = function (a) {
	return {$: 30, a: a};
};
var $author$project$Main$UpdateDistanceMarkerInterval = function (a) {
	return {$: 40, a: a};
};
var $author$project$Main$UpdateDistanceMarkerSegmentEnds = function (a) {
	return {$: 41, a: a};
};
var $author$project$Main$UpdateFontSize = function (a) {
	return {$: 26, a: a};
};
var $author$project$Main$UpdateIntensityTau = function (a) {
	return {$: 31, a: a};
};
var $author$project$Main$UpdateLabelHeightGain = function (a) {
	return {$: 29, a: a};
};
var $author$project$Main$UpdateSplitWaypoint = F2(
	function (a, b) {
		return {$: 36, a: a, b: b};
	});
var $author$project$Main$UpdateSplits = function (a) {
	return {$: 32, a: a};
};
var $author$project$Main$UpdateTrackHeight = function (a) {
	return {$: 27, a: a};
};
var $author$project$Main$UpdateTrackThickness = function (a) {
	return {$: 28, a: a};
};
var $author$project$Main$viewElevationProfileOptions = function (state) {
	var ep = state.a;
	return _List_fromArray(
		[
			A2(
			$author$project$Main$optionGroup,
			'Font size',
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('1'),
							$elm$html$Html$Attributes$max('50'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromFloat(ep.W)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toFloat,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault(15),
									$author$project$Main$UpdateFontSize)))
						]),
					_List_Nil)
				])),
			A2(
			$author$project$Main$optionGroup,
			'Track height',
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('1'),
							$elm$html$Html$Attributes$max('400'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromInt(ep.ac)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toInt,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault(200),
									$author$project$Main$UpdateTrackHeight)))
						]),
					_List_Nil)
				])),
			A2(
			$author$project$Main$optionGroup,
			'Track thickness',
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('0.1'),
							$elm$html$Html$Attributes$max('10'),
							$elm$html$Html$Attributes$step('0.1'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromFloat(ep.ad)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toFloat,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault(1),
									$author$project$Main$UpdateTrackThickness)))
						]),
					_List_Nil)
				])),
			A2(
			$author$project$Main$optionGroup,
			'Label height',
			_List_fromArray(
				[
					A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('range'),
							$elm$html$Html$Attributes$min('0.5'),
							$elm$html$Html$Attributes$max('3'),
							$elm$html$Html$Attributes$step('0.1'),
							$elm$html$Html$Attributes$value(
							$elm$core$String$fromFloat(ep.X)),
							$elm$html$Html$Events$onInput(
							A2(
								$elm$core$Basics$composeR,
								$elm$core$String$toFloat,
								A2(
									$elm$core$Basics$composeR,
									$elm$core$Maybe$withDefault(1),
									$author$project$Main$UpdateLabelHeightGain)))
						]),
					_List_Nil)
				])),
			A2(
			$author$project$Main$optionGroup,
			'Intensity',
			$elm$core$List$concat(
				_List_fromArray(
					[
						_List_fromArray(
						[
							A3(
							$author$project$Main$viewButton,
							_List_fromArray(
								[
									A2($elm$html$Html$Attributes$style, 'width', '100%')
								]),
							ep.G ? 'HIDE INTENSITY' : 'SHOW INTENSITY',
							$author$project$Main$ShowIntensity(!ep.G))
						]),
						ep.G ? _List_fromArray(
						[
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$type_('range'),
									$elm$html$Html$Attributes$min('100'),
									$elm$html$Html$Attributes$max('20000'),
									$elm$html$Html$Attributes$step('50'),
									$elm$html$Html$Attributes$value(
									$elm$core$String$fromFloat(ep.O)),
									$elm$html$Html$Events$onInput(
									A2(
										$elm$core$Basics$composeR,
										$elm$core$String$toFloat,
										A2(
											$elm$core$Basics$composeR,
											$elm$core$Maybe$withDefault(500),
											$author$project$Main$UpdateIntensityTau)))
								]),
							_List_Nil),
							$elm$html$Html$text(
							'τ = ' + ($elm$core$String$fromFloat(ep.O) + 'm'))
						]) : _List_Nil
					]))),
			A2(
			$author$project$Main$optionGroup,
			'Splits',
			$elm$core$List$concat(
				_List_fromArray(
					[
						_List_fromArray(
						[
							A2(
							$elm$html$Html$select,
							_List_fromArray(
								[
									$elm$html$Html$Events$onInput(
									function (v) {
										if (v === 'waypoints') {
											return $author$project$Main$SetSplitMode(1);
										} else {
											return $author$project$Main$SetSplitMode(0);
										}
									})
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$option,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$value('equidistant'),
											$elm$html$Html$Attributes$selected(!ep.J)
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Equidistant')
										])),
									A2(
									$elm$html$Html$option,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$value('waypoints'),
											$elm$html$Html$Attributes$selected(ep.J === 1)
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('By waypoints')
										]))
								]))
						]),
						function () {
						var _v1 = ep.J;
						if (!_v1) {
							return _List_fromArray(
								[
									A2(
									$elm$html$Html$input,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$type_('range'),
											$elm$html$Html$Attributes$min('1'),
											$elm$html$Html$Attributes$max('10'),
											$elm$html$Html$Attributes$value(
											$elm$core$String$fromInt(ep.aa)),
											$elm$html$Html$Events$onInput(
											A2(
												$elm$core$Basics$composeR,
												$elm$core$String$toInt,
												A2(
													$elm$core$Basics$composeR,
													$elm$core$Maybe$map(
														A2($elm$core$Basics$clamp, 1, 10)),
													A2(
														$elm$core$Basics$composeR,
														$elm$core$Maybe$withDefault(1),
														$author$project$Main$UpdateSplits))))
										]),
									_List_Nil),
									$elm$html$Html$text(
									$elm$core$String$fromInt(ep.aa))
								]);
						} else {
							var selectedIndices = ep.l;
							var indexed = A2(
								$elm$core$Maybe$withDefault,
								_List_Nil,
								A2(
									$elm$core$Maybe$map,
									A2(
										$elm$core$Basics$composeR,
										function ($) {
											return $.c;
										},
										A2(
											$elm$core$Basics$composeR,
											function ($) {
												return $.f;
											},
											$author$project$Main$indexedEffectiveWaypoints)),
									$author$project$Main$maybeFromloadableResource(state.b)));
							var dropdownRow = F2(
								function (splitListPos, selectedWaypointIdx) {
									var waypointOption = function (_v2) {
										var waypointIdx = _v2.a;
										var wp = _v2.b;
										return A2(
											$elm$html$Html$option,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$value(
													$elm$core$String$fromInt(waypointIdx)),
													$elm$html$Html$Attributes$selected(
													_Utils_eq(waypointIdx, selectedWaypointIdx))
												]),
											_List_fromArray(
												[
													$elm$html$Html$text(
													wp.bn + (' (' + (A2($author$project$Main$formatKm, 1, wp.az) + ')')))
												]));
									};
									return A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												A2($elm$html$Html$Attributes$style, 'display', 'flex'),
												A2($elm$html$Html$Attributes$style, 'gap', '0.5em'),
												A2($elm$html$Html$Attributes$style, 'align-items', 'center')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$select,
												_List_fromArray(
													[
														$elm$html$Html$Events$onInput(
														function (val) {
															return A2(
																$elm$core$Maybe$withDefault,
																$author$project$Main$Ignore,
																A2(
																	$elm$core$Maybe$map,
																	$author$project$Main$UpdateSplitWaypoint(splitListPos),
																	$elm$core$String$toInt(val)));
														})
													]),
												A2($elm$core$List$map, waypointOption, indexed)),
												A2(
												$elm$html$Html$button,
												_List_fromArray(
													[
														$elm$html$Html$Events$onClick(
														$author$project$Main$RemoveSplitWaypoint(splitListPos)),
														$elm$html$Html$Attributes$class('button-4')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Remove')
													]))
											]));
								});
							return _Utils_ap(
								A2($elm$core$List$indexedMap, dropdownRow, selectedIndices),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Events$onClick($author$project$Main$AddSplitWaypoint),
												$elm$html$Html$Attributes$class('button-4'),
												$elm$html$Html$Attributes$disabled(
												_Utils_cmp(
													$elm$core$List$length(selectedIndices),
													$elm$core$List$length(indexed)) > -1)
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Add')
											]))
									]));
						}
					}()
					]))),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil),
			$author$project$Main$viewTotalDistanceOptions(state),
			A2(
			$author$project$Main$optionGroup,
			'Marker interval',
			$elm$core$List$concat(
				_List_fromArray(
					[
						_List_fromArray(
						[
							A3(
							$author$project$Main$checkbox,
							_Utils_eq(ep.M, $elm$core$Maybe$Nothing),
							$author$project$Main$UpdateDistanceMarkerInterval(
								_Utils_eq(ep.M, $elm$core$Maybe$Nothing) ? $elm$core$Maybe$Just(10000) : $elm$core$Maybe$Nothing),
							'Auto interval')
						]),
						function () {
						var _v3 = ep.M;
						if (!_v3.$) {
							var interval = _v3.a;
							return _List_fromArray(
								[
									A2(
									$elm$html$Html$input,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$type_('range'),
											$elm$html$Html$Attributes$min('1'),
											$elm$html$Html$Attributes$max('50'),
											$elm$html$Html$Attributes$step('1'),
											$elm$html$Html$Attributes$value(
											$elm$core$String$fromFloat(interval / 1000)),
											$elm$html$Html$Events$onInput(
											A2(
												$elm$core$Basics$composeR,
												$elm$core$String$toFloat,
												A2(
													$elm$core$Basics$composeR,
													$elm$core$Maybe$withDefault(10),
													function (km) {
														return $author$project$Main$UpdateDistanceMarkerInterval(
															$elm$core$Maybe$Just(km * 1000));
													})))
										]),
									_List_Nil),
									$elm$html$Html$text(
									A2($author$project$Main$formatKm, 0, interval))
								]);
						} else {
							return _List_Nil;
						}
					}(),
						_List_fromArray(
						[
							A3(
							$author$project$Main$checkbox,
							ep.N,
							$author$project$Main$UpdateDistanceMarkerSegmentEnds(!ep.N),
							'Mark segment start/finish')
						])
					]))),
			A2($elm$html$Html$hr, _List_Nil, _List_Nil)
		]);
};
var $author$project$Main$RequestLocation = {$: 12};
var $author$project$Main$SetTrackingInterval = function (a) {
	return {$: 14, a: a};
};
var $author$project$Main$ToggleTracking = {$: 13};
var $author$project$Main$UpdatePosition = function (a) {
	return {$: 42, a: a};
};
var $author$project$Location$locationErrorToString = function (err) {
	switch (err) {
		case 0:
			return 'Location permission denied';
		case 1:
			return 'Position unavailable';
		default:
			return 'Location request timed out';
	}
};
var $author$project$Main$viewLocationOptions = function (state) {
	var _v0 = state.b;
	if (_v0.$ === 3) {
		var tracks = _v0.a;
		var maxDist = $author$project$Main$lastTrackpointDistance(tracks.c.bM);
		var locationStatus = function (text) {
			return A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '0.8em'),
						A2($elm$html$Html$Attributes$style, 'margin', '0.5em 0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(text)
					]));
		};
		return $elm$core$List$concat(
			_List_fromArray(
				[
					_List_fromArray(
					[
						A2($elm$html$Html$hr, _List_Nil, _List_Nil),
						A2(
						$author$project$Main$optionGroup,
						'Position',
						A2(
							$elm$core$List$cons,
							A2(
								$elm$html$Html$input,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$type_('range'),
										$elm$html$Html$Attributes$min('0'),
										$elm$html$Html$Attributes$max(
										$elm$core$String$fromFloat(maxDist)),
										$elm$html$Html$Attributes$step('100'),
										$elm$html$Html$Attributes$value(
										$elm$core$String$fromFloat(
											A2($elm$core$Maybe$withDefault, 0, state.cg))),
										$elm$html$Html$Events$onInput(
										A2($elm$core$Basics$composeR, $elm$core$String$toFloat, $author$project$Main$UpdatePosition)),
										$elm$html$Html$Attributes$disabled(state.y)
									]),
								_List_Nil),
							function () {
								var _v1 = state.cg;
								if (!_v1.$) {
									return _List_fromArray(
										[
											A3(
											$author$project$Main$viewButton,
											_List_fromArray(
												[
													A2($elm$html$Html$Attributes$style, 'width', '100%')
												]),
											'Clear position',
											$author$project$Main$UpdatePosition($elm$core$Maybe$Nothing))
										]);
								} else {
									return _List_Nil;
								}
							}())),
						A3(
						$author$project$Main$viewButton,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'width', '100%')
							]),
						state.y ? 'Stop Tracking' : 'Start Tracking',
						$author$project$Main$ToggleTracking),
						A3(
						$author$project$Main$viewButton,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'width', '100%')
							]),
						'Refresh Location',
						$author$project$Main$RequestLocation)
					]),
					state.y ? _List_fromArray(
					[
						A2(
						$author$project$Main$optionGroup,
						'Interval: ' + ($elm$core$String$fromInt(state.U) + 's'),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$input,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$type_('range'),
										$elm$html$Html$Attributes$min('10'),
										$elm$html$Html$Attributes$max('300'),
										$elm$html$Html$Attributes$step('10'),
										$elm$html$Html$Attributes$value(
										$elm$core$String$fromInt(state.U)),
										$elm$html$Html$Events$onInput(
										A2(
											$elm$core$Basics$composeR,
											$elm$core$String$toInt,
											A2(
												$elm$core$Basics$composeR,
												$elm$core$Maybe$withDefault(60),
												$author$project$Main$SetTrackingInterval)))
									]),
								_List_Nil)
							]))
					]) : _List_Nil,
					function () {
					var _v2 = _Utils_Tuple3(state.Y, state.ag, state.y);
					if (!_v2.a.$) {
						var err = _v2.a.a;
						return _List_fromArray(
							[
								locationStatus(
								$author$project$Location$locationErrorToString(err))
							]);
					} else {
						if (!_v2.b.$) {
							var _v3 = _v2.a;
							var loc = _v2.b.a;
							return _List_fromArray(
								[
									locationStatus(
									'Accuracy: ' + ($elm$core$String$fromFloat(
										$elm$core$Basics$round(loc.a_ * 10) / 10) + 'm'))
								]);
						} else {
							if (_v2.c) {
								var _v4 = _v2.a;
								var _v5 = _v2.b;
								return _List_fromArray(
									[
										locationStatus('No location fix')
									]);
							} else {
								var _v6 = _v2.a;
								var _v7 = _v2.b;
								return _List_Nil;
							}
						}
					}
				}()
				]));
	} else {
		return _List_Nil;
	}
};
var $author$project$Main$ExportState = {$: 52};
var $author$project$Main$ImportStateFromFile = {$: 54};
var $author$project$Main$ImportStateFromUrl = function (a) {
	return {$: 57, a: a};
};
var $elm$html$Html$form = _VirtualDom_node('form');
var $elm$html$Html$Attributes$placeholder = $elm$html$Html$Attributes$stringProperty('placeholder');
var $elm$virtual_dom$VirtualDom$MayPreventDefault = function (a) {
	return {$: 2, a: a};
};
var $elm$html$Html$Events$preventDefaultOn = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$MayPreventDefault(decoder));
	});
var $author$project$Main$viewStateExportImport = _List_fromArray(
	[
		A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('flex-container'),
				$elm$html$Html$Attributes$class('column'),
				A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
				A2($elm$html$Html$Attributes$style, 'gap', '0.25em')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('flex-container'),
						A2($elm$html$Html$Attributes$style, 'gap', '0.25em'),
						A2($elm$html$Html$Attributes$style, 'width', '100%')
					]),
				_List_fromArray(
					[
						A3(
						$author$project$Main$viewButton,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'flex', '1')
							]),
						'export state',
						$author$project$Main$ExportState),
						A3(
						$author$project$Main$viewButton,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'flex', '1')
							]),
						'import state',
						$author$project$Main$ImportStateFromFile)
					])),
				A2(
				$elm$html$Html$form,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$Events$preventDefaultOn,
						'submit',
						A2(
							$elm$json$Json$Decode$map,
							function (url) {
								return _Utils_Tuple2(
									$author$project$Main$ImportStateFromUrl(url),
									true);
							},
							A2(
								$elm$json$Json$Decode$at,
								_List_fromArray(
									['target', '0', 'value']),
								$elm$json$Json$Decode$string))),
						$elm$html$Html$Attributes$class('flex-container'),
						A2($elm$html$Html$Attributes$style, 'width', '100%'),
						A2($elm$html$Html$Attributes$style, 'gap', '0.25em')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('url'),
								$elm$html$Html$Attributes$placeholder('state URL'),
								A2($elm$html$Html$Attributes$style, 'flex', '1'),
								A2($elm$html$Html$Attributes$style, 'min-width', '0')
							]),
						_List_Nil),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('submit')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('fetch')
							]))
					]))
			]))
	]);
var $author$project$Main$NavigateToNext = {$: 9};
var $author$project$Main$NavigateToPrevious = {$: 8};
var $author$project$Main$viewTrackNavigationButtons = function (state) {
	var _v0 = state.b;
	if (_v0.$ === 3) {
		var tracks = _v0.a;
		return $elm$core$List$concat(
			_List_fromArray(
				[
					(!$elm$core$List$isEmpty(tracks.as)) ? _List_fromArray(
					[
						A3(
						$author$project$Main$viewButton,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'width', '100%')
							]),
						'PREV',
						$author$project$Main$NavigateToPrevious)
					]) : _List_Nil,
					(!$elm$core$List$isEmpty(tracks.aF)) ? _List_fromArray(
					[
						A3(
						$author$project$Main$viewButton,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'width', '100%')
							]),
						'NEXT',
						$author$project$Main$NavigateToNext)
					]) : _List_Nil
				]));
	} else {
		return _List_Nil;
	}
};
var $author$project$Main$viewOptionsPanel = function (state) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('flex-container'),
				$elm$html$Html$Attributes$class('column'),
				A2($elm$html$Html$Attributes$style, 'overflow', 'auto'),
				$elm$html$Html$Attributes$class('narrow'),
				A2($elm$html$Html$Attributes$style, 'flex-shrink', '0')
			]),
		(!state._) ? _List_fromArray(
			[
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(
						$author$project$Main$ShowOptions(true)),
						A2($elm$html$Html$Attributes$style, 'transform', 'rotate(90deg)'),
						A2($elm$html$Html$Attributes$style, 'white-space', 'nowrap'),
						A2($elm$html$Html$Attributes$style, 'width', '1em'),
						A2($elm$html$Html$Attributes$style, 'margin', 'auto 0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('(show options)')
					]))
			]) : _List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('options'),
						A2($elm$html$Html$Attributes$style, 'margin', 'auto 0')
					]),
				$elm$core$List$concat(
					_List_fromArray(
						[
							_List_fromArray(
							[
								A2(
								$elm$html$Html$h2,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Options')
									])),
								A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										$elm$html$Html$Events$onClick(
										$author$project$Main$ShowOptions(false))
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('(hide)')
									])),
								A2($elm$html$Html$hr, _List_Nil, _List_Nil)
							]),
							_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('flex-container'),
										$elm$html$Html$Attributes$class('column'),
										A2($elm$html$Html$Attributes$style, 'justify-content', 'center'),
										A2($elm$html$Html$Attributes$style, 'align-items', 'center')
									]),
								$elm$core$List$concat(
									_List_fromArray(
										[
											_List_fromArray(
											[
												A3(
												$author$project$Main$viewButton,
												_List_fromArray(
													[
														A2($elm$html$Html$Attributes$style, 'width', '100%')
													]),
												'upload GPX',
												$author$project$Main$OpenFileBrowser)
											]),
											$author$project$Main$viewTrackNavigationButtons(state)
										]))),
								A2($elm$html$Html$hr, _List_Nil, _List_Nil)
							]),
							$author$project$Main$viewStateExportImport,
							_List_fromArray(
							[
								A2($elm$html$Html$hr, _List_Nil, _List_Nil)
							]),
							$author$project$Main$viewCategoryFilterOptions(state),
							_List_fromArray(
							[
								A2(
								$author$project$Main$optionGroup,
								'View',
								_List_fromArray(
									[
										A2(
										$elm$html$Html$select,
										_List_fromArray(
											[
												$elm$html$Html$Events$onInput(
												function (v) {
													if (v === 'live') {
														return $author$project$Main$SetViewMode(0);
													} else {
														return $author$project$Main$SetViewMode(1);
													}
												})
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$option,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$value('static'),
														$elm$html$Html$Attributes$selected(state.q === 1)
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Static')
													])),
												A2(
												$elm$html$Html$option,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$value('live'),
														$elm$html$Html$Attributes$selected(!state.q)
													]),
												_List_fromArray(
													[
														$elm$html$Html$text('Live')
													]))
											]))
									]))
							]),
							function () {
							var _v1 = state.q;
							if (!_v1) {
								var ep = state.a;
								return _List_fromArray(
									[
										A2(
										$author$project$Main$optionGroup,
										'Live window',
										_List_fromArray(
											[
												$elm$html$Html$text(
												'Lookbehind: ' + A2($author$project$Main$formatKm, 1, ep.C)),
												A2(
												$elm$html$Html$input,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$type_('range'),
														$elm$html$Html$Attributes$min('0'),
														$elm$html$Html$Attributes$max('50000'),
														$elm$html$Html$Attributes$step('500'),
														$elm$html$Html$Attributes$value(
														$elm$core$String$fromFloat(ep.C)),
														$elm$html$Html$Events$onInput(
														A2(
															$elm$core$Basics$composeR,
															$elm$core$String$toFloat,
															A2(
																$elm$core$Basics$composeR,
																$elm$core$Maybe$withDefault(2000),
																$author$project$Main$UpdateLiveLookbehind)))
													]),
												_List_Nil),
												$elm$html$Html$text(
												'Lookahead: ' + A2($author$project$Main$formatKm, 1, ep.B)),
												A2(
												$elm$html$Html$input,
												_List_fromArray(
													[
														$elm$html$Html$Attributes$type_('range'),
														$elm$html$Html$Attributes$min('0'),
														$elm$html$Html$Attributes$max('200000'),
														$elm$html$Html$Attributes$step('500'),
														$elm$html$Html$Attributes$value(
														$elm$core$String$fromFloat(ep.B)),
														$elm$html$Html$Events$onInput(
														A2(
															$elm$core$Basics$composeR,
															$elm$core$String$toFloat,
															A2(
																$elm$core$Basics$composeR,
																$elm$core$Maybe$withDefault(5000),
																$author$project$Main$UpdateLiveLookahead)))
													]),
												_List_Nil)
											]))
									]);
							} else {
								var _v2 = state.I;
								if (!_v2.$) {
									return _List_fromArray(
										[
											A3($author$project$Main$viewButton, _List_Nil, 'Download splits', $author$project$Main$DownloadSplitsGpx)
										]);
								} else {
									return _List_Nil;
								}
							}
						}(),
							function () {
							var _v3 = state.K;
							switch (_v3) {
								case 0:
									return $author$project$Main$viewElevationProfileOptions(state);
								case 1:
									return $author$project$Main$viewCuesheetOptionsPanel(state);
								default:
									return _List_Nil;
							}
						}(),
							$author$project$Main$viewLocationOptions(state)
						])))
			]));
};
var $author$project$Main$DismissStateDecodeError = {$: 1};
var $elm$html$Html$strong = _VirtualDom_node('strong');
var $author$project$Main$viewStateDecodeError = function (maybeError) {
	if (maybeError.$ === 1) {
		return _List_Nil;
	} else {
		var error = maybeError.a;
		return _List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'background', '#fff3cd'),
						A2($elm$html$Html$Attributes$style, 'color', '#856404'),
						A2($elm$html$Html$Attributes$style, 'padding', '0.75em 1em'),
						A2($elm$html$Html$Attributes$style, 'margin', '0.5em'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '4px'),
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'flex-start'),
						A2($elm$html$Html$Attributes$style, 'gap', '1em'),
						A2($elm$html$Html$Attributes$style, 'width', '100%')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Failed to restore saved state: ')
									])),
								$elm$html$Html$text(
								A2($elm$core$String$left, 500, error))
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$DismissStateDecodeError),
								A2($elm$html$Html$Attributes$style, 'background', 'none'),
								A2($elm$html$Html$Attributes$style, 'border', 'none'),
								A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
								A2($elm$html$Html$Attributes$style, 'font-size', '1.2em'),
								A2($elm$html$Html$Attributes$style, 'color', '#856404')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('×')
							]))
					]))
			]);
	}
};
var $author$project$Main$SwitchTab = function (a) {
	return {$: 10, a: a};
};
var $author$project$Main$viewTabBar = function (activeTab) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('flex-container'),
				A2($elm$html$Html$Attributes$style, 'justify-content', 'center'),
				A2($elm$html$Html$Attributes$style, 'gap', '0'),
				A2($elm$html$Html$Attributes$style, 'padding', '0.5em')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(
						$author$project$Main$SwitchTab(0)),
						$elm$html$Html$Attributes$class('button-4'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '4px 0 0 4px'),
						(!activeTab) ? A2($elm$html$Html$Attributes$style, 'font-weight', 'bold') : A2($elm$html$Html$Attributes$style, 'opacity', '0.7')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Elevation Profile')
					])),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(
						$author$project$Main$SwitchTab(1)),
						$elm$html$Html$Attributes$class('button-4'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '0'),
						(activeTab === 1) ? A2($elm$html$Html$Attributes$style, 'font-weight', 'bold') : A2($elm$html$Html$Attributes$style, 'opacity', '0.7')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Cuesheet')
					])),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(
						$author$project$Main$SwitchTab(2)),
						$elm$html$Html$Attributes$class('button-4'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '0 4px 4px 0'),
						(activeTab === 2) ? A2($elm$html$Html$Attributes$style, 'font-weight', 'bold') : A2($elm$html$Html$Attributes$style, 'opacity', '0.7')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Waypoints')
					]))
			]));
};
var $author$project$Main$viewTrackNavigation = function (tracks) {
	var hasPrev = !$elm$core$List$isEmpty(tracks.as);
	var hasNext = !$elm$core$List$isEmpty(tracks.aF);
	return ((!hasPrev) && (!hasNext)) ? $elm$html$Html$text('') : A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('flex-container'),
				A2($elm$html$Html$Attributes$style, 'justify-content', 'center'),
				A2($elm$html$Html$Attributes$style, 'gap', '1em'),
				A2($elm$html$Html$Attributes$style, 'padding', '0.5em')
			]),
		_List_fromArray(
			[
				hasPrev ? A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick($author$project$Main$NavigateToPrevious)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('← Prev track')
					])) : $elm$html$Html$text(''),
				$elm$html$Html$text(
				'Track ' + ($elm$core$String$fromInt(
					$elm$core$List$length(tracks.as) + 1) + (' of ' + $elm$core$String$fromInt(
					($elm$core$List$length(tracks.as) + 1) + $elm$core$List$length(tracks.aF))))),
				hasNext ? A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick($author$project$Main$NavigateToNext)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Next track →')
					])) : $elm$html$Html$text('')
			]));
};
var $author$project$Main$ResetWaypoints = {$: 25};
var $author$project$Main$WaypointDeleted = F2(
	function (a, b) {
		return {$: 21, a: a, b: b};
	});
var $author$project$Main$WaypointDistanceChange = F2(
	function (a, b) {
		return {$: 19, a: a, b: b};
	});
var $author$project$Main$WaypointNameChange = F2(
	function (a, b) {
		return {$: 20, a: a, b: b};
	});
var $elm$html$Html$span = _VirtualDom_node('span');
var $author$project$Main$viewDeletedWaypoint = F2(
	function (i, ew) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'border', '1px solid #eee'),
					A2($elm$html$Html$Attributes$style, 'border-radius', '6px'),
					A2($elm$html$Html$Attributes$style, 'padding', '0.5em'),
					A2($elm$html$Html$Attributes$style, 'opacity', '0.5'),
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
					A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
					A2($elm$html$Html$Attributes$style, 'gap', '0.5em')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'text-decoration', 'line-through')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(ew.x.bn)
						])),
					A3(
					$author$project$Main$viewButton,
					_List_Nil,
					'Undo',
					A2($author$project$Main$WaypointDeleted, i, false))
				]));
	});
var $author$project$Main$WaypointCategoryAdd = F2(
	function (a, b) {
		return {$: 23, a: a, b: b};
	});
var $author$project$Main$WaypointCategoryToggle = F3(
	function (a, b, c) {
		return {$: 22, a: a, b: b, c: c};
	});
var $author$project$Main$WaypointNewCategoryInput = F2(
	function (a, b) {
		return {$: 24, a: a, b: b};
	});
var $elm$html$Html$Events$targetChecked = A2(
	$elm$json$Json$Decode$at,
	_List_fromArray(
		['target', 'checked']),
	$elm$json$Json$Decode$bool);
var $elm$html$Html$Events$onCheck = function (tagger) {
	return A2(
		$elm$html$Html$Events$on,
		'change',
		A2($elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetChecked));
};
var $author$project$Main$viewWaypointCategories = F4(
	function (idx, waypointCategories, allCategories, newCatInput) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
					A2($elm$html$Html$Attributes$style, 'gap', '0.4em')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'display', 'flex'),
							A2($elm$html$Html$Attributes$style, 'flex-wrap', 'wrap'),
							A2($elm$html$Html$Attributes$style, 'gap', '0.25em')
						]),
					A2(
						$elm$core$List$map,
						function (cat) {
							var isChecked = A2($elm$core$List$member, cat, waypointCategories);
							return A2(
								$elm$html$Html$label,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'display', 'inline-flex'),
										A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
										A2($elm$html$Html$Attributes$style, 'gap', '0.15em'),
										A2($elm$html$Html$Attributes$style, 'padding', '0.15em 0.4em'),
										A2($elm$html$Html$Attributes$style, 'border-radius', '4px'),
										A2($elm$html$Html$Attributes$style, 'border', '1px solid #ccc'),
										A2($elm$html$Html$Attributes$style, 'font-size', '0.85em'),
										A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
										A2(
										$elm$html$Html$Attributes$style,
										'background',
										isChecked ? '#e0edff' : '#fff'),
										A2($elm$html$Html$Attributes$style, 'white-space', 'nowrap')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$input,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$type_('checkbox'),
												$elm$html$Html$Attributes$checked(isChecked),
												$elm$html$Html$Events$onCheck(
												A2($author$project$Main$WaypointCategoryToggle, idx, cat)),
												A2($elm$html$Html$Attributes$style, 'margin', '0')
											]),
										_List_Nil),
										$elm$html$Html$text(cat)
									]));
						},
						allCategories)),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'display', 'flex'),
							A2($elm$html$Html$Attributes$style, 'gap', '0.25em'),
							A2($elm$html$Html$Attributes$style, 'align-items', 'center')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$type_('text'),
									$elm$html$Html$Attributes$placeholder('New category...'),
									$elm$html$Html$Attributes$value(newCatInput),
									$elm$html$Html$Events$onInput(
									$author$project$Main$WaypointNewCategoryInput(idx)),
									A2($elm$html$Html$Attributes$style, 'flex', '1'),
									A2($elm$html$Html$Attributes$style, 'min-width', '0')
								]),
							_List_Nil),
							A3(
							$author$project$Main$viewButton,
							_List_Nil,
							'Add',
							A2($author$project$Main$WaypointCategoryAdd, idx, ''))
						]))
				]));
	});
var $author$project$Main$viewWaypointsTab = F2(
	function (state, tracks) {
		var maxDistance = $author$project$Main$lastTrackpointDistance(tracks.c.bM);
		var anyWaypointEdited = A2(
			$elm$core$List$any,
			function (ew) {
				return ew.L || (!_Utils_eq(ew.k, $author$project$Main$emptyOverrides));
			},
			tracks.c.f);
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
					A2($elm$html$Html$Attributes$style, 'gap', '0.5em'),
					A2($elm$html$Html$Attributes$style, 'padding', '0.5em')
				]),
			_List_fromArray(
				[
					anyWaypointEdited ? A3($author$project$Main$viewButton, _List_Nil, 'Reset Waypoints', $author$project$Main$ResetWaypoints) : $elm$html$Html$text(''),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'display', 'flex'),
							A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
							A2($elm$html$Html$Attributes$style, 'gap', '0.5em')
						]),
					A2(
						$elm$core$List$filterMap,
						function (_v0) {
							var i = _v0.a;
							var ew = _v0.b;
							var wp = $author$project$Main$effectiveWaypoint(ew);
							var predicates = $author$project$Main$waypointPredicates(state);
							return (!A2(
								$elm$core$List$all,
								function (f) {
									return f(wp);
								},
								predicates)) ? $elm$core$Maybe$Nothing : (ew.L ? $elm$core$Maybe$Just(
								A2($author$project$Main$viewDeletedWaypoint, i, ew)) : $elm$core$Maybe$Just(
								A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											A2($elm$html$Html$Attributes$style, 'border', '1px solid #ddd'),
											A2($elm$html$Html$Attributes$style, 'border-radius', '6px'),
											A2($elm$html$Html$Attributes$style, 'padding', '0.5em'),
											A2($elm$html$Html$Attributes$style, 'display', 'flex'),
											A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
											A2($elm$html$Html$Attributes$style, 'gap', '0.4em'),
											A2($elm$html$Html$Attributes$style, 'background', '#fafafa')
										]),
									_List_fromArray(
										[
											A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													A2($elm$html$Html$Attributes$style, 'display', 'flex'),
													A2($elm$html$Html$Attributes$style, 'gap', '0.4em'),
													A2($elm$html$Html$Attributes$style, 'align-items', 'center')
												]),
											_List_fromArray(
												[
													A2(
													$elm$html$Html$input,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$type_('number'),
															$elm$html$Html$Attributes$min('0'),
															A3($elm$core$Basics$composeR, $elm$core$String$fromFloat, $elm$html$Html$Attributes$max, maxDistance),
															$elm$html$Html$Attributes$value(
															$elm$core$String$fromFloat(wp.az)),
															$elm$html$Html$Events$onInput(
															A2(
																$elm$core$Basics$composeR,
																$elm$core$String$toFloat,
																A2(
																	$elm$core$Basics$composeR,
																	$elm$core$Maybe$withDefault(1000),
																	$author$project$Main$WaypointDistanceChange(i)))),
															A2($elm$html$Html$Attributes$style, 'width', '7em'),
															A2($elm$html$Html$Attributes$style, 'flex-shrink', '0')
														]),
													_List_Nil),
													A2(
													$elm$html$Html$input,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$type_('text'),
															$elm$html$Html$Attributes$placeholder('Waypoint name...'),
															$elm$html$Html$Attributes$value(wp.bn),
															$elm$html$Html$Events$onInput(
															$author$project$Main$WaypointNameChange(i)),
															A2($elm$html$Html$Attributes$style, 'flex', '1'),
															A2($elm$html$Html$Attributes$style, 'min-width', '0')
														]),
													_List_Nil),
													A3(
													$author$project$Main$viewButton,
													_List_Nil,
													'X',
													A2($author$project$Main$WaypointDeleted, i, true))
												])),
											A4(
											$author$project$Main$viewWaypointCategories,
											i,
											wp.a1,
											A2(
												$elm$core$List$filter,
												function (c) {
													return !_Utils_eq(c, $author$project$Main$unknownCategory);
												},
												$elm$core$Dict$keys(state.d)),
											A2(
												$elm$core$Maybe$withDefault,
												'',
												A2($elm$core$Dict$get, i, state.Q)))
										]))));
						},
						A2($elm$core$List$indexedMap, $elm$core$Tuple$pair, tracks.c.f)))
				]));
	});
var $author$project$Main$view = function (_v0) {
	var state = _v0.o;
	return A2(
		$elm$browser$Browser$Document,
		'Route',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('flex-container'),
						$elm$html$Html$Attributes$class('row'),
						$elm$html$Html$Attributes$class('page'),
						A2($elm$html$Html$Attributes$style, 'height', '100%')
					]),
				_Utils_ap(
					$author$project$Main$viewStateDecodeError(state.ab),
					function () {
						var _v1 = state.b;
						switch (_v1.$) {
							case 0:
								return _List_fromArray(
									[
										$author$project$Main$viewOptionsPanel(state),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('flex-container'),
												$elm$html$Html$Attributes$class('column'),
												$elm$html$Html$Attributes$class('wide'),
												A2($elm$html$Html$Attributes$style, 'height', '100%'),
												A2($elm$html$Html$Attributes$style, 'overflow', 'auto')
											]),
										_List_fromArray(
											[$author$project$Main$viewLandingPage]))
									]);
							case 1:
								return _List_fromArray(
									[
										$author$project$Main$viewOptionsPanel(state),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('flex-container'),
												$elm$html$Html$Attributes$class('column'),
												$elm$html$Html$Attributes$class('wide'),
												A2($elm$html$Html$Attributes$style, 'height', '100%'),
												A2($elm$html$Html$Attributes$style, 'overflow', 'auto')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$p,
												_List_Nil,
												_List_fromArray(
													[
														$elm$html$Html$text('Loading...')
													]))
											]))
									]);
							case 2:
								var err = _v1.a;
								return _List_fromArray(
									[
										$author$project$Main$viewOptionsPanel(state),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('flex-container'),
												$elm$html$Html$Attributes$class('column'),
												$elm$html$Html$Attributes$class('wide'),
												A2($elm$html$Html$Attributes$style, 'height', '100%'),
												A2($elm$html$Html$Attributes$style, 'overflow', 'auto')
											]),
										_List_fromArray(
											[
												$author$project$Main$viewErrorPanel(
												'There was an error processing your file. Please fix any error and try again.\n\nError: ' + (($elm$core$String$length(err) > 1000) ? (A2($elm$core$String$left, 500, err) + ('...\n\n...' + A2($elm$core$String$right, 500, err))) : err))
											]))
									]);
							default:
								var tracks = _v1.a;
								return _List_fromArray(
									[
										$author$project$Main$viewOptionsPanel(state),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('flex-container'),
												$elm$html$Html$Attributes$class('column'),
												$elm$html$Html$Attributes$class('wide'),
												A2($elm$html$Html$Attributes$style, 'height', '100%'),
												A2($elm$html$Html$Attributes$style, 'overflow', 'auto')
											]),
										_List_fromArray(
											[
												$author$project$Main$viewTabBar(state.K),
												$author$project$Main$viewTrackNavigation(tracks),
												function () {
												var _v2 = state.K;
												switch (_v2) {
													case 0:
														return A2($author$project$Main$viewElevationProfileTab, state, tracks);
													case 1:
														return A2($author$project$Main$viewCuesheetTab, state, tracks);
													default:
														return A2($author$project$Main$viewWaypointsTab, state, tracks);
												}
											}()
											]))
									]);
						}
					}()))
			]));
};
var $author$project$Main$main = $elm$browser$Browser$application(
	{
		b4: $author$project$Main$init,
		cc: function (_v0) {
			return $author$project$Main$Ignore;
		},
		cd: function (_v1) {
			return $author$project$Main$Ignore;
		},
		cq: $author$project$Main$subscriptions,
		ct: $author$project$Main$update,
		cu: $author$project$Main$view
	});
_Platform_export({'Main':{'init':$author$project$Main$main(
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$elm$json$Json$Decode$null($elm$core$Maybe$Nothing),
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$value)
			])))(0)}});}(this));
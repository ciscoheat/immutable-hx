# Immutable

A Haxe 4 library for making your local vars immutable with

`haxelib install immutable` 

`-lib immutable`

```haxe
class YourClass implements Immutable
{
	// For immutable class fields, use the Haxe 4 "final" keyword.
	public final test : String;

	public function new() {
		test = "Final";
	}

	public function test() {
		var a = 123;
		a = 234; // *** Compilation error

		@mutable var b = 123;
		b = 234; // Ok
	}

	public function test2(a : String, @mutable b : Int) {
		a = "changed"; // *** Compilation error
		b = 123; // Ok
	}
}
```

Since the library is enforcing this at compile-time, it won't slow down your code. It may affect compilation time a little, so in certain cases you may choose to disable all checking with `-D disable-immutable`.

## ES6-style

When implementing `Immutable`, vars will behave like [const](https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Statements/const) and [let](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/let), used in modern javascript:
	
ES6            | Haxe
-------------- | ---------------------
const a = 123; | var a = 123;
let b = 234;   | @mutable var b = 234;

## Limitations

If the compiler cannot find any type information, it cannot make the var immutable.

## Problems?

Please open an issue if you happened to trick the library, or if you think something is conceptually or semantically wrong. Using [Reflect](http://api.haxe.org/Reflect.html) isn't tricking though, it's intentional!

[![Build Status](https://travis-ci.org/ciscoheat/immutable-hx.svg?branch=master)](https://travis-ci.org/ciscoheat/immutable-hx)

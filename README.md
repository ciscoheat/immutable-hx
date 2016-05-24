# Immutable

Make your classes and local vars immutable with

`haxelib install immutable` 

`-lib immutable`

```haxe
class YourClass implements Immutable
{
	public var test : String;

	// Fields can be mutable, but will emit a compiler warning:
	@mutable public var specialCase : String;

	public function new() {
		test = "It's ok to assign in the constructor";
	}

	public function test() {
		var a = 123;
		a = 234; // *** Compilation error

		@mutable var b = 123;
		b = 234; // Ok

		this.test = "mutated!"; // *** Compilation error, incl. external access
		this.specialCase = "special"; // Ok
	}
}
```

It's using macros for enforcing this at compile-time, so it won't slow down your code.

## ES6-style

When implementing `Immutable`, vars will behave like [const](https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Statements/const) and [let](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/let), used in modern javascript:
	
ES6            | Haxe
-------------- | ---------------------
const a = 123; | var a = 123;
let b = 234;   | @mutable var b = 234;

## For local vars only

If you want your class vars and properties to behave as usual, you can implement `ImmutableLocalVars` instead, and it will only affect vars in methods. This can be useful if you have another library that rewrites the class fields, like [DataClass](https://github.com/ciscoheat/dataclass).

## Problems?

Please open an issue if you happened to trick the library, or if you think something is conceptually or semantically wrong. Using [Reflect](http://api.haxe.org/Reflect.html) isn't tricking though, it's intentional!

[![Build Status](https://travis-ci.org/ciscoheat/immutable-hx.svg?branch=master)](https://travis-ci.org/ciscoheat/immutable-hx)

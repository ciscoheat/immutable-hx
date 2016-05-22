# Immutable

Make your classes immutable with

`haxelib install immutable`

```haxe
class YourClass implements Immutable
{
	public var test : String;

	@mutable public var specialCase : String;

	public function new() {
		test = "It's ok to assign in the constructor";
	}

	public function test() {
		var a = 123;
		a = 234; // Illegal

		@mutable var b = 123;
		b = 234; // Ok

		this.test = "mutated!"; // Illegal, including outside class
		this.specialCase = "special"; // Ok
	}
}
```

Please open an issue if you happened to trick the library, or if you think something is conceptually or semantically wrong.

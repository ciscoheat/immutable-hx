package subpack;

class AlsoImmutable implements Immutable 
{
	@mutable public static var staticTest : Float;
	
	public function new() {}
	
	public function test(start : Float) {
		@mutable var a = 123.0;
		a = 456.0 + start;
		if (start < 0) new RunTests.Mutable().eat(a + start);
		
		staticTest = 123.123;
	}
}
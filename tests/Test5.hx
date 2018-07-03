class Test5 implements Immutable
{
	public static function main() {}
	
	public function test() {
		var a = 1;
		function b(a : String) {
			a = "reassigning a should fail";
			return a;
		}
		b("test");
	}
}
class Test5 implements Immutable
{
	public static function main() {}
	
	public function test() {
		var a = [1,2,3,4];
		// In short lambdas, args are mutable
		// but you can still define immutable local vars.
		return a.filter(i -> {
			var j = 10;
			i += 1;
			j = 20;
			i < 3;
		});
	}
}
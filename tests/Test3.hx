class Test3 implements Immutable
{
	public static function main() {}
	
	public function test() {
		var b : { final b: Date; } = {b: Date.now()};
		b = {b: Date.now()};
	}
}

import sys.FileSystem;
import sys.io.File;

// Start from top directory with
// haxe -cp tests -main RunFailureTests --interp
class RunFailureTests {
	static function main() {
		var src = "./tests/RunTests.hx";
		var bak = "./tests/RunTests.hx.bak";
		var status = 0;

		try {
			File.copy(src, bak);

			var content = File.getContent(src);

			// Extract all test comments
			var tests = [for(i in 0...content.length-8) {
				if(content.substr(i, 8) == "//TEST: ") i;
			}];

			var args = ['tests.hxml', '-cp', 'src', '--interp'];
			var count = 0;

			for(pos in tests) {
				Sys.println('Compilation failure test ${++count} of ${tests.length}');

				// Uncomment one test comment at a time
				File.saveContent(src, content.substr(0, pos) + content.substr(pos+8));
				if(Sys.command('haxe', args) == 0) {
					// If it didn't fail, then the test failed.
					status = 1;
					break;
				}
			}
		} catch(e : Dynamic) {
			trace(e);
			status = 1;
		}

		File.copy(bak, src);
		FileSystem.deleteFile(bak);
		
		Sys.println("*** Completed, status: " + status);

		Sys.exit(status);
	}
}
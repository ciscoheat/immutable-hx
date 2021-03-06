import sys.FileSystem;
import haxe.io.Path;
import sys.io.Process;

using buddy.Should;

class RunTests extends buddy.SingleSuite
{	
	public function new() {
		describe("Immutable", {
			it("should be able to use assignments normally.", {
				var i = new LocalImmutable();
				i.testOneVar().should.be("ok");
				i.testArgs("aaa").should.be("aaa");
				i.testMultipleVars().should.be("123");
				i.testReassignment().should.be(123);
				i.testFunctions().should.be("testtest");
				i.testComplexType().should.be("txt");
				i.testFunctionVars().should.be("1test5");
				i.testClosureVars().should.be("testclosure");
				i.testMutableClosureVars().should.be("mutabletestclosure");
				i.testShortLambdas().should.containExactly([1,2,3]);
				i.testShortLambdasWithLocalImmutable().should.containExactly([1,2,3]);
				i.testMutableUndefinedVar().should.beGreaterThan(123);
			});

			it("should be able to make vars mutable with @mutable metadata", {
				var i = new LocalImmutable();
				i.testMutableVar().should.be(2);
				i.testMutableArg(1).should.be(2);
				i.testMutable().should.be("1testmutable");
			});

			it("should prevent assignments to local vars at compile time", {
				try {
					// Detect where the tests are 
					// (assumes tests directory somewhere above or alongside bin)
					var path = FileSystem.absolutePath(".");
					while(!FileSystem.exists(Path.join([path, 'tests', 'RunTests.hx']))) {
						path = Path.withoutDirectory(path);
					}

					var testFile = ~/^Test(\d+)/;
					var testFiles = [for(f in FileSystem.readDirectory(Path.join([path, 'tests']))) {
						if(testFile.match(f)) f;
					}];

					var args = ['-cp', 'tests', '-cp', 'src', '--interp'];
					#if nodejs
					args = args.concat(['-lib', 'hxnodejs']);
					#end

					for (test in testFiles) {
						#if sys
						var process = new Process('haxe', args.concat([test]));
						if(process.exitCode() == 0) {
						#else
						if(Sys.command('haxe', args.concat([test])) == 0) {
						#end
							// If it didn't fail, then the test failed.
							fail('$test failed - compilation passed.');
							break;
						}
					}
				} catch(e : Dynamic) {
					fail(e);
				}
			});
		});
	}
}

class LocalImmutable implements Immutable
{
	public function new() {
	}
	
	public function testOneVar() {
		var a = "ok";
		return a;
	}

	public function testMultipleVars() {
		var a = "1", b = "2", c = "3";
		return [a,b,c].join("");
	}

	public function testArgs(a : String) {
		var b : {final b: String;} = {b: a};
		return b.b;
	}

	public function testReassignment() {
		var a = "ok";
		var a = 123;
		return a;
	}

	public function testFunctions() {
		var a : Int = 1;
		function b(a : String) {
			return a + a.split("").join("");
		}
		return b("test");
	}

	public function testFunctionVars() {
		var a = 1;
		var b = function (a : String) {
			return a + a.length;
		}
		return b(a + "test");
	}

	public function testClosureVars() {
		var a = "test";
		function b(c : String) {
			return a + c;
		}
		return b("closure");
	}

	public function testMutableUndefinedVar() {
		@mutable var a;
		a = 123.00 + Math.random();
		return a;
	}

	public function testMutableClosureVars() {
		@mutable var a = "test";
		function b(c : String) {
			a = "mutabletest";
			return a + c;
		}
		return b("closure");
	}

	public function testLackOfTypeInformation() {
		var a = [1,2,3,4,5,6,7];
		@mutable var b = a.concat([8]);
		return b;
	}

	public function testShortLambdas() {
		var a = [1,2,3,4,5,6,7];
		var b = a.filter(i -> i < 4);
		return b;
	}

	public function testShortLambdasWithLocalImmutable() {
		var a = [1,2,3,4];
		return a.filter(i -> {
			i -= 1;
			var j : Int = i * 10;
			j < 30;
		});
	}

	public function testComplexType() {
		var b = new haxe.io.Path("/test/file.txt");
		return b.ext;
	}

	public function testMutableVar() {
		@mutable var a = 1;
		a = 2;
		return a;
	}

	public function testMutableArg(@mutable m : Int) {
		if(m < 2) m = 2;
		return m;
	}

	public function testMutable() {
		var a = 1;
		function b(@mutable a : String) {
			a = a + "mutable";
			return a;
		}
		return b(a + "test");
	}
}

import subpack.AlsoImmutable;
using buddy.Should;

// Every line in this file starting with TEST: should create a failure if uncommented.
// This is tested with RunFailureTests.hx

class RunTests extends buddy.SingleSuite
{	
	public function new() {
		describe("Immutable", {
			var i : VeryImmutable;
			
			beforeEach( { i = new VeryImmutable(); } );
			
			it("should not allow field assignments outside constructor", {
				i.test(123).should.be(456);
			});
			
			it("should transform all public class vars to prop(default, null)", {
				i.test(123).should.be(456);
				//TEST: i.publicVar = "illegal";
				//TEST: i.privateVar.should.be("illegal");
			});
			
			it("should not allow any non-var assignments", {
				i.test(123).should.be(456);
			});
			
			it("should allow mutable vars when using @mutable", {
				i.test(123).should.be(456);
				i.mutableVar.should.be("mutable");
				
				i.mutableVar = "ok";
				VeryImmutable.staticMutableVar = 1;
				//TEST: VeryImmutable.staticVar = 1;
			});
			
			it("should work for classes in subpackages", {
				new AlsoImmutable().test(3.14);
			});
			
			it("should work on static fields", {
				(function() ImmuTest.mainTest(1)).should.not.throwAnything();
			});
			
			it("should not optimize away vars", {
				ImmuTest.main().should.be(1);
			});
			
			it("should ignore class fields when implementing ImmutableLocalVars", {
				var local = new LocalImmutable().test();
				local.mutable.should.be("ok");
			});
			
			#if (haxe_ver >= 3.3)
			it("should handle @mutable on function arguments", {
				new MutableArguments().test("hello", "immutable").should.be("HELLO");
			});
			#end
			
			it("should allow map.set calls on generic maps.", {
				(function() new MapSet().test()).should.not.throwAnything();
			});
		});
	}
}

class ImmuTest implements Immutable {
	public static function mainTest(start) {
		var a = 1;
		//TEST: a = start + 2;
		VeryImmutable.staticMutableVar = a;
	}
	
	public static function main() {
		var a = 1;
		//TEST: Macro.assign(a, 2);
		return a;
	}
}

class Mutable {
	public static var staticMutableVar = 0;
	
	public var publicVar = 0;
	
	public function new() { }

	// 3.3 compiler is too good at optimizing, this is required to keep the test code!
	public function eat(o : Dynamic) {
		trace(o);
	}
}

class VeryImmutable implements Immutable {
	public static var staticVar : Int;
	public var publicVar : String;
	
	public var propDef(default, null) : Int;
	
	@mutable public static var staticMutableVar : Int;
	@mutable public var mutableVar : String;
	
	//TEST: public var setter(default, set) : Int; function set_setter(v) return setter = v;
	//TEST: public var setter2(default, default) : Int;
	
	var privateVar : String;
	var t : Mutable; // To keep the code without optimizations
	
	public function new() {
		this.t = new Mutable();
		this.publicVar = "set";
		privateVar = "set";		
	}
	
	public function test(start) {
		// ----- Static tests -----
		staticMutableVar = 1;
		VeryImmutable.staticMutableVar = 2;
		//TEST: staticVar = 1;
		//TEST: VeryImmutable.staticVar = 1;
		
		// ----- Instance tests -----
		mutableVar = "mutable";
		this.mutableVar = "mutable";
		//TEST: publicVar = "illegal";
		//TEST: privateVar = "illegal";
		//TEST: this.propDef = 1;
		//TEST: propDef = 1;
		
		// ----- Basic assignment -----
		var mutableVar = 999;
		var test = publicVar;		
		var number = 0;
		var number2 = number + 123;
		//TEST: mutableVar = 1000;
		//TEST: number += 123;
		//TEST: mutableVar = 1000+start; t.eat(mutableVar);
		//TEST: test = Std.string(start); t.eat(test);
		//TEST: number += (start + 123); t.eat(number);
		
		// ----- Method calls -----
		var testArray = [];
		testArray.push(1);
		//TEST: testArray = []; t.eat(testArray);
		
		// ----- Calling other objects -----
		var mutable = new Mutable();
		mutable.publicVar = 1;
		Mutable.staticMutableVar = 1;

		// ----- Assigning this to a local var -----
		var self = this;
		//TEST: self.publicVar = "illegal";
		var self2 = function() return this;
		//TEST: self2().privateVar = "illegal";
		
		// ----- Mutable var -----
		@mutable var exception = start;
		exception = exception + 77;
		
		if (true) {
			// In different scope
			exception += 100;
			
			// New, immutable var in different scope
			var exception = 999;
			//TEST: exception = 888 + start; t.eat(exception);
			
			if (!false) {
				// Yet another scope
				//TEST: exception = 456 - start; t.eat(exception);
			}
		}
		
		exception += 100;
		
		// ----- Macro rewrites -----
		Macro.assign(exception, exception + 56);
		//TEST: Macro.assign(number, 555-start); t.eat(number);
		
		return exception;
	}
}

class VeryImmutable2 implements Immutable
{
	public function new() { }

	// Dynamic methods aren't allowed
	//TEST: public dynamic function dynamicTest() { return "illegal"; }
	
	// Inline should be allowed
	public inline function test() {
		return "inline";
	}
}

class LocalImmutable implements ImmutableLocalVars
{
	public var mutable : String;
	
	public function new() {
		mutable = "true";
	}
	
	public function test() {
		var test = "ok";
		//TEST: test = "illegal";
		mutable = test;
		return this;
	}
}

// Should emit a warning:
@:analyzer(local_dce)
class OptimizedImmutable implements Immutable
{
	public function new() {}
}

#if (haxe_ver >= 3.3)
class MutableArguments implements Immutable
{
	public function new() { }

	public function test(@mutable a : String, b : String) {
		function modify(@mutable b : String) {
			b = b.toUpperCase();
			return b;
		}
		//xTEST: b = a; // Cannot use this test because of the #if
		a = modify(a);
		return a;
	}
}
#end

// Maps are abstracted, special care must be taken to allow their assignments.
class MapSet implements Immutable
{
	var map = new Map<String, String>();
	var fullClassmap : Map<OptimizedImmutable, MapSet>;
	var mixed = new Map<Int, MapSet>();
	
	public function new() {
		fullClassmap = new Map<OptimizedImmutable, MapSet>();
	}
	
	public function test() {
		var localmap = new Map<Int, String>();
		var fullmap = new Map<OptimizedImmutable, MapSet>();
		
		map.set("a", "a");
		map.get("a");
		map.remove("a");

		mixed.set(1, new MapSet());
		mixed.get(1);
		mixed.remove(1);

		localmap.set(1, "1");
		localmap.get(1);
		localmap.remove(1);
		
		var m = new OptimizedImmutable();
		
		fullmap.set(m, new MapSet());
		fullmap.set(new OptimizedImmutable(), new MapSet());
		fullmap.get(m);
		fullmap.remove(m);
		
		fullClassmap.set(m, new MapSet());
		fullClassmap.set(new OptimizedImmutable(), new MapSet());
		fullClassmap.get(m);
		fullClassmap.remove(m);		
		
		// Try reassigning the maps
		//TEST: localmap = new Map<Int, String>();
		//TEST: fullmap = new Map<OptimizedImmutable, MapSet>();
		//TEST: this.map = new Map<String, String>();
		//TEST: fullClassmap = new Map<OptimizedImmutable, MapSet>();
		//TEST: mixed = new Map<Int, MapSet>();
	}
}

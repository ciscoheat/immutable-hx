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
		});
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
	
	//TEST: public var setter(default, set) : Int;
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
	public function new() {}
}

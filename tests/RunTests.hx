using buddy.Should;

class RunTests extends buddy.SingleSuite
{	
	public function new() {
		describe("Immutable", {
			var i : VeryImmutable;
			
			beforeEach( { i = new VeryImmutable(); } );
			
			it("should not allow field assignments outside constructor", {
				i.test().should.be(456);
			});
			
			it("should transform all public class vars to prop(default, null)", {
				i.test().should.be(456);
				//TEST: i.publicVar = "illegal";
			});
			
			it("should not allow any non-var assignments", {
				i.test().should.be(456);
			});
			
			it("should allow mutable vars when using @mutable", {
				i.test().should.be(456);
				i.mutableVar.should.be("mutable");
				
				i.mutableVar = "ok";
				VeryImmutable.staticMutableVar = 1;
				//TEST: VeryImmutable.staticVar = 1;
			});
		});
	}
}

class Mutable {
	public static var staticMutable = 0;
	
	public var publicVar = 0;
	
	public function new() {}
}

class VeryImmutable implements Immutable {
	public static var staticVar : Int;
	public var publicVar : String;
	
	@mutable public static var staticMutableVar : Int;
	@mutable public var mutableVar : String;
	
	//TEST: public var setter(default, set) : Int;
	//TEST: public var setter2(default, default) : Int;
	
	var privateVar : String;
	
	public function new() {
		this.publicVar = "set";
		privateVar = "set";
	}
	
	public function test() {
		// ----- Static tests -----
		staticMutableVar = 1;
		//TEST: staticVar = 1;
		//TEST: VeryImmutable.staticVar = 1;
		
		// ----- Instance tests -----
		mutableVar = "mutable";
		//TEST: publicVar = "illegal";		
		
		// ----- Basic assignment -----
		var mutableVar = 999;		
		var test = publicVar;		
		var number = 0;
		var number2 = number + 123;
		//TEST: test = "illegal";		
		//TEST: number += 123;
		
		// ----- Method calls -----
		var testArray = [];
		testArray.push(1);
		//TEST: testArray = [];
		
		// ----- Calling other objects -----
		var mutable = new Mutable();
		mutable.publicVar = 1;
		Mutable.staticMutable = 1;

		// ----- Assigning to this and calling -----
		var self = this;
		//TEST: self.publicVar = "illegal";
		
		// ----- Mutable var -----
		@mutable var exception = 123;
		exception = 234;
		
		if (true) {
			// In different scope
			exception = 345;
			
			// New, immutable var in different scope
			var exception = 999;
			//TEST: exception = 888;
			
			if (!false) {
				// Yet another scope
				//TEST: exception = 456;
			}
		}
		
		exception += 100;
		
		// ----- Macro rewrites -----
		Macro.assign(exception, exception + 11);
		//TEST: Macro.assign(number, 555);
		
		return exception;
	}
}

class VeryImmutable2 implements Immutable
{
	public function new() {}
}

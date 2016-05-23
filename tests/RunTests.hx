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
				//i.publicVar = "illegal";
			});
			
			it("should not allow any non-var assignments", {
				i.test().should.be(456);
			});
			
			it("should allow mutable vars when using @mutable", {
				i.test().should.be(456);
				i.mutableVar.should.be("mutable");
				
				i.mutableVar = "ok";
				i.mutableVar.should.be("ok");
				
				VeryImmutable.staticMutableVar = 1;
				//VeryImmutable.staticVar = 1;
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
	
	//public var setter(default, set) : Int;
	//public var setter2(default, default) : Int;
	
	var privateVar : String;
	
	public function new() {
		this.publicVar = "set";
		privateVar = "set";
	}
	
	public function test() {
		// ----- Static tests -----
		staticMutableVar = 1;
		//staticVar = 1;
		
		// ----- Instance tests -----
		mutableVar = "mutable";
		//publicVar = "illegal";		
		
		// ----- Basic assignment -----
		var mutableVar = 999;		
		var test = publicVar;		
		var number = 0;
		var number2 = number + 123;
		//test = "illegal";		
		//number += 123;
		
		// ----- Method calls -----
		var testArray = [];
		testArray.push(1);
		//testArray = [];
		
		// ----- Calling other objects -----
		var mutable = new Mutable();
		mutable.publicVar = 1;
		Mutable.staticMutable = 1;

		// ----- Assigning to this and calling -----
		var self = this;
		//self.publicVar = "illegal";
		
		// ----- Mutable var -----
		@mutable var exception = 123;
		exception = 234;
		
		if (true) {
			// In different scope
			exception = 345;
			
			// New, immutable var in different scope
			var exception = 999;
			//exception = 888;
			
			if (!false) {
				// Yet another scope
				//exception = 456;
			}
		}
		
		exception += 100;
		
		// ----- Macro rewrites -----
		Macro.assign(exception, exception + 11);
		//Macro.assign(number, 555);
		
		return exception;
	}
}

class VeryImmutable2 implements Immutable
{
	public function new() {}
}

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
				//i.publicVar = "illegal";
				i.test().should.be(456);
			});
			
			it("should not allow any non-var assignments", {
				i.test().should.be(456);
			});
			
			it("should allow mutable vars when using @mutable", {
				i.test().should.be(456);
				i.mutableVar.should.be("mutable");
				
				i.mutableVar = "ok";
				i.mutableVar.should.be("ok");
			});
		});
	}
}

class VeryImmutable implements Immutable {
	public var publicVar : String;
	
	@mutable public var mutableVar : String;
	
	//public var setter(default, set) : Int;
	//public var setter2(default, default) : Int;
	
	var privateVar : String;
	
	public function new() {
		this.publicVar = "set";
		privateVar = "set";
	}
	
	public function test() {
		//publicVar = "illegal";
		
		mutableVar = "mutable";
		
		var test = publicVar;		
		//test = "illegal";
		
		var number = 0;
		//number += 123;
		
		var number2 = number + 123;
		
		var testArray = [];
		testArray.push(1);		
		//testArray = [];
		
		@mutable var exception = 123;
		exception = 234;

		if (true) {
			exception = 345;
			
			var exception = 999;
			//exception = 888;
			
			if (!false) {
				//exception = 456;
			}
		}
		
		exception += 111;
		
		return exception;
	}
}
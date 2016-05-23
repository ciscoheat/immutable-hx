#if macro
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;
using StringTools;
#end

@:autoBuild(Immutable.ImmutableBuilder.build()) interface Immutable {}

#if macro
class ImmutableBuilder
{	
	static function build() return new ImmutableBuilder().makeImmutable();
	
	//////////////////////////////////////////////////////////////////////////
	
	var fieldNames : Array<String>;
	var mutableFields : Array<String>;
	
	function new() {
		fieldNames = [for (field in Context.getBuildFields()) field.name];
		
		mutableFields = [for (field in Context.getBuildFields()) 
			if (field.meta.find(function(m) return m.name == "mutable") != null)
				field.name
		];
	}
	
	function makeImmutable() : Array<Field> {
		return Context.getBuildFields().map(function(field) return switch field.kind {
			case FVar(t, e):
				if (e != null) preventAssignments(false, [], e);
				
				if(!mutableFields.has(field.name))
					field.kind = FProp('default', 'null', t, e);
					
				field;
			
			case FProp(get, set, t, e):
				if (set != 'null' && set != 'never' && !mutableFields.has(field.name)) 
					Context.error("Setters not allowed in an immutable class. Use only 'null' or 'never'.", field.pos);
					
				if (e != null) preventAssignments(false, [], e);
				field;
				
			case FFun(f):
				if (f.expr != null) preventAssignments(field.name == "new", [], f.expr);
				field;
		});		
	}
	
	function assignmentError(e : Expr) Context.error("Cannot make assignments in an immutable class without marking the var with @mutable.", e.pos);
	
	function preventAssignments(inConstructor : Bool, mutables : Array<String>, e : Expr) {
		switch e.expr {
			case EBlock(exprs):
				var newMutables = mutables.copy();
				for (e2 in exprs) preventAssignments(inConstructor, newMutables, e2);
				return;
			
			case EBinop(OpAssign, e1, e2) | EBinop(OpAssignOp(_), e1, e2):
				var field = e1.toString();
				
				if (!mutableFields.has(field) && !mutables.has(field)) {
					if (inConstructor) {
						var classField = field.startsWith("this.") ? field.substr(5) : field;
						if (!fieldNames.has(classField) && !mutables.has(field)) assignmentError(e);					
					}
					else {
						assignmentError(e);
					} 					
				}
				
			case EVars(vars):
				for (v in vars) mutables.remove(v.name);
				
			case EMeta(s, { expr: EVars(vars), pos: _ }) if (s.name == "mutable"):
				for (v in vars) mutables.push(v.name);
				e.expr = EVars(vars); // Need to remove the meta, otherwise it won't compile
				
				// Run through the vars expr separately, to avoid them being muted again in the EVars switch
				for (v in vars) preventAssignments(inConstructor, mutables, v.expr);
				return;
				
			case _: 
		}
		
		e.iter(preventAssignments.bind(inConstructor, mutables));
	}
}
#end

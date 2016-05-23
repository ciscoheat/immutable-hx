#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.MacroStringTools;
using haxe.macro.ExprTools;
using haxe.macro.TypedExprTools;

using Lambda;
using StringTools;
#end

@:autoBuild(Immutable.ImmutableBuilder.build()) interface Immutable {}

#if macro
class ImmutableBuilder
{
	static var immutableTypes = new Map<String, ImmutableBuilder>();
	static var typesChecked = false;
	
	static function build() {
		var cls = Context.getLocalClass().get();
		var buildFields = Context.getBuildFields();

		var fieldNames = [for (field in buildFields) field.name];
		var mutableFieldNames = [for (field in buildFields) 
			if (field.meta.find(function(m) return m.name == "mutable") != null) {
				Context.warning('Field ${field.name} marked as mutable in immutable class', field.pos);
				field.name;
			}
		];
		
		var className = cls.pack.toDotPath(cls.name);
		var builder = new ImmutableBuilder(className, fieldNames, mutableFieldNames);
		
		immutableTypes.set(className, builder);

		Context.onGenerate(function(types) {
			if (typesChecked) return;
			typesChecked = true;

			for (type in types) switch type {
				case TInst(t, _):
					var inst = t.get();
					var typeName = inst.pack.toDotPath(inst.name);
					if (immutableTypes.exists(typeName)) {
						for (field in inst.fields.get()) if (field.expr() != null) {
							var builder = immutableTypes.get(typeName);
							builder.preventTypedAssignments(field.name == "get", field.expr());
						}
					}
				case _:
			}
		});

		return builder.makeImmutable(buildFields);
	}
	
	//////////////////////////////////////////////////////////////////////////
	
	var className : String;
	var fieldNames : Array<String>;
	var mutableFieldNames : Array<String>;
	
	function new(className, fieldNames, mutableFieldNames) {
		this.className = className;
		this.fieldNames = fieldNames;
		this.mutableFieldNames = mutableFieldNames;
	}
	
	function makeImmutable(fields : Array<Field>) : Array<Field> {
		return fields.map(function(field) return switch field.kind {
			case FVar(t, e):
				if (e != null) renameMutableVars(false, [], e);
				
				if(!mutableFieldNames.has(field.name))
					field.kind = FProp('default', 'null', t, e);
					
				field;
			
			case FProp(get, set, t, e):
				if (set != 'null' && set != 'never' && !mutableFieldNames.has(field.name)) 
					Context.error("Setters are not allowed in an immutable class. Use only 'null' or 'never'.", field.pos);
					
				if (e != null) renameMutableVars(false, [], e);
				field;
				
			case FFun(f):
				if (f.expr != null) renameMutableVars(field.name == "new", [], f.expr);
				field;
		});		
	}
	
	function typedAssignmentError(e : TypedExpr) {
		Context.error("Cannot make assignments in an immutable class without marking the var with @mutable.", e.pos);
	}
	
	function renameMutableVars(inConstructor : Bool, mutables : Array<String>, e : Expr) {
		switch e.expr {
			// New block, create a new scope for mutable vars
			case EBlock(exprs):
				var newMutableScope = mutables.copy();
				for (e2 in exprs) renameMutableVars(inConstructor, newMutableScope, e2);
				return;
			
			// New vars, remove mutables in the current scope if they exist
			case EVars(vars):
				for (v in vars) mutables.remove(v.name);
				
			// Rename all mutable constants, so they won't be checked later
			case EConst(CIdent(s)) if(mutables.has(s)): 
				e.expr = EConst(CIdent('__mutable_$s'));
				
			case EMeta(s, { expr: EVars(vars), pos: _ }) if (s.name == "mutable"):
				// Run through the vars expressions separately, to avoid them being immutable in the EVars switch.
				// Run them before setting mutables, because the var expressions aren't in that scope.
				for (v in vars) renameMutableVars(inConstructor, mutables, v.expr);
				
				// Set mutables for the current scope
				for (v in vars) if (!mutables.has(v.name)) {
					mutables.push(v.name);
					v.name = '__mutable_' + v.name;
				}
				
				// Need to remove the meta, otherwise it won't compile
				e.expr = EVars(vars);
				return;
				
			case _: 
		}
		
		e.iter(renameMutableVars.bind(inConstructor, mutables));
	}
	
	function preventTypedAssignments(inConstructor : Bool, e : TypedExpr) {
		switch e.expr {
			case TBinop(OpAssign, e1, e2) | TBinop(OpAssignOp(_), e1, e2):
				switch(e1.expr) {
					// Test for instance field assignment. Only allowed if mutable or in constructor.
					case TField({ expr: TConst(TThis), t: _, pos: _ }, fa): 
						switch fa {
							case FInstance(_, _, cf):
								var field = cf.get().name;
								if (!mutableFieldNames.has(field) && !(inConstructor && fieldNames.has(field)))
									typedAssignmentError(e);
								
							case _: 
								typedAssignmentError(e); null;
						}
					
					// Test for static field assignment. Only allowed if mutable.
					case TField({expr: TTypeExpr(m), t: _, pos: _ }, fa):
						switch m {
							case TClassDecl(c):
								var cls = c.get();
								if (cls.pack.toDotPath(cls.name) == className) {
									switch fa {
										case FStatic(_, cf):
											var field = cf.get().name;
											if (!mutableFieldNames.has(field)) typedAssignmentError(e);
										case _:
									}
								}
							case _:
								typedAssignmentError(e); null;
						}
						
					// Test for local vars assigned to its own class.
					case TField({expr: TLocal(v), t: t, pos: _}, fa):
						switch fa {
							case FInstance(c, _, cf):
								var cls = c.get();
								if (cls.pack.toDotPath(cls.name) == className) {
									var field = cf.get().name;
									if (!mutableFieldNames.has(field) && !(inConstructor && fieldNames.has(field)))
										typedAssignmentError(e);
								}
							case _:
						}
						
					case TLocal(v):
						if (!v.name.startsWith("__mutable_")) typedAssignmentError(e);
						
					case _: 
						typedAssignmentError(e); null;
				}				
			case _: 
		}
		
		e.iter(preventTypedAssignments.bind(inConstructor));
	}	
}
#end

package immutable;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.MacroStringTools;
using haxe.macro.ExprTools;
using haxe.macro.TypedExprTools;

using Lambda;
using StringTools;

class BuildImmutableClass
{
	static var immutableTypes = new Map<String, BuildImmutableClass>();
	static var typesChecked = false;
	
	static function build(onlyLocalVars : Bool) {
		var cls : ClassType = Context.getLocalClass().get();
		var buildFields = Context.getBuildFields();
		
		// Remove some optimizations to avoid mutable vars being modified by the compiler
		cls.meta.add(":analyzer", [macro no_local_dce], cls.pos);
		
		var fieldNames = [for (field in buildFields) field.name];
		var mutableFieldNames = [for (field in buildFields) 
			if (field.meta.find(function(m) return m.name == "mutable") != null) {
				Context.warning('Field ${field.name} marked as mutable in immutable class', field.pos);
				field.name;
			}
		];
		
		var className = cls.pack.toDotPath(cls.name);
		var builder = new BuildImmutableClass(className, fieldNames, mutableFieldNames, onlyLocalVars);
		
		if(!Context.defined("display")) {
			immutableTypes.set(className, builder);

			Context.onGenerate(function(types) {
				if (typesChecked) return;
				typesChecked = true;

				for (type in types) switch type {
					case TInst(t, _):
						var inst = t.get();
						var typeName = inst.pack.toDotPath(inst.name);
						if (immutableTypes.exists(typeName)) {
							
							var meta = inst.meta.get();
							
							var localDce = meta.find(function(m)
								return m.name == ":analyzer" && 
									m.params.length > 0 &&
									m.params[0].expr.equals(EConst(CIdent("local_dce")))
							);
							
							if (localDce != null) Context.warning(
								"Using @:analyzer(local_dce) can give unpredictable behavior on an Immutable class.",
							inst.pos);

							var allClassFields = inst.fields.get()
								.concat(inst.statics.get())								
								.concat(inst.overrides.map(function(i) return i.get()));
								
							if (inst.constructor != null) allClassFields.push(inst.constructor.get());

							var builder = immutableTypes.get(typeName);
							
							for (field in allClassFields) {
								if(!builder.onlyLocalVars) switch field.kind {
									case FVar(_, write):
										if (write != AccNo && write != AccNever && !builder.mutableFieldNames.has(field.name)) {
											Context.error(
												"Setters are not allowed in an Immutable class. Use only 'null' or 'never'.", 
											field.pos);
										}
									case FMethod(k):
										if (k == MethDynamic) Context.error(
											"Dynamic methods aren't allowed in an Immutable class.", 
										field.pos);
								}
								
								if (field.expr() != null) {									
									builder.preventAssignments(field.name == "new", field.expr());
								}
							}
						}
					case _:
				}
			});
		}

		return builder.makeImmutable(buildFields);
	}
	
	//////////////////////////////////////////////////////////////////////////
	
	var className : String;
	var fieldNames : Array<String>;
	var mutableFieldNames : Array<String>;
	
	var onlyLocalVars : Bool;
	
	function new(className, fieldNames, mutableFieldNames, onlyLocalVars) {
		this.className = className;
		this.fieldNames = fieldNames;
		this.mutableFieldNames = mutableFieldNames;
		this.onlyLocalVars = onlyLocalVars;
	}
	
	function makeImmutable(fields : Array<Field>) : Array<Field> {
		return fields.map(function(field) return switch field.kind {
			case FVar(t, e):
				if (e != null) renameMutableVars(false, [], e);
				
				// Rewrite var to var(default, null)
				if(!onlyLocalVars && !mutableFieldNames.has(field.name))
					field.kind = FProp('default', 'null', t, e);
					
				field;
			
			case FProp(get, set, t, e):
				if (e != null) renameMutableVars(false, [], e);
				field;
				
			case FFun(f):
				if (f.expr != null) renameMutableVars(field.name == "new", [], f.expr);
				field;
		});		
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
				
			case EConst(CIdent(s)) if(mutables.has(s)): 
				e.expr = EConst(CIdent('__mutable_$s'));
				
			case EMeta(s, { expr: EVars(vars), pos: _ }) if (s.name == "mutable"):
				// Run through the vars expressions separately, to avoid them being immutable in the EVars switch.
				// Run them before setting mutables, because the var expressions aren't in that scope.
				for (v in vars) renameMutableVars(inConstructor, mutables, v.expr);
				
				// Set mutables for the current scope and rename the var so
				// it can be identified as mutable.
				for (v in vars) if (!mutables.has(v.name)) {
					mutables.push(v.name);
					v.name = '__mutable_${v.name}';
				}
				
				// Need to remove the meta, otherwise it won't compile
				e.expr = EVars(vars);
				return;
				
			case _: 
		}
		
		e.iter(renameMutableVars.bind(inConstructor, mutables));
	}
	
	function typedAssignmentError(e : TypedExpr) {
		Context.error("Cannot make assignments in an immutable class without marking the var with @mutable.", e.pos);
	}
	
	function preventAssignments(inConstructor : Bool, e : TypedExpr) {
		switch e.expr {
			case TBinop(OpAssign, e1, _) | TBinop(OpAssignOp(_), e1, _): switch(e1.expr) {
				case TField({ expr: fieldExpr, t: t, pos: _ }, fa): 
					var skipClassFieldTests = if(onlyLocalVars) true else switch t {
						// Skip instance references not pointing to the own class
						case TInst(clsType, _) if (clsType.get().pack.toDotPath(clsType.get().name) != className):
							true;
						
						// Skip type references not of the same class
						case TType(defType, _):
							var name = defType.get().name;
							var extract = ~/^Class<(.*)>$/;

							if (extract.match(name)) {
								defType.get().pack.toDotPath(extract.matched(1)) != className;
							} 
							else true;
						
						case _:
							false;
					}
					
					if (!skipClassFieldTests) switch fieldExpr {
						
						// Testing instance field ("this") assignments
						case TConst(TThis):
							switch fa {
								case FInstance(_, _, cf):
									var field = cf.get().name;
									if (!mutableFieldNames.has(field) && !(inConstructor && fieldNames.has(field)))
										typedAssignmentError(e);
									
								case _: 
									typedAssignmentError(e);
							}
							
						// Testing static field assignments
						case TTypeExpr(_):
							switch fa {
								case FStatic(_, cf):
									var field = cf.get().name;
									if (!mutableFieldNames.has(field)) typedAssignmentError(e);
								case _:
									typedAssignmentError(e);
							}
						case _:
							typedAssignmentError(e);
					}
					
				case TLocal(v):
					if (!v.name.startsWith("__mutable_")) {
						if (!Reflect.hasField(v, "meta")) typedAssignmentError(e);

						// The compiler can generate assignments, trust them for now.
						#if (haxe_ver < 3.3)
						var meta : Array<Dynamic> = untyped v.meta;
						#else
						// Working properly in 3.3
						var meta = v.meta.get();
						#end
						if (!meta.exists(function(m) return m.name == ":compilerGenerated"))
							typedAssignmentError(e);
					}
					
				case _: 
					typedAssignmentError(e);
			}				
			case _: 
		}
		
		e.iter(preventAssignments.bind(inConstructor));
	}	
}
#end

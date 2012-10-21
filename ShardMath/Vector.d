module ShardMath.Vector;
private import std.conv;

private import std.math;
private import std.traits;

/// A structure representing an N-Dimensional vector of T type.
struct Vector(int N, T) if(N >= 2) {	
	
private:		

	/// If T is a floating point type, this is alased to T; otherwise, float.
	/// This is used for operations that do not have a meaningful result for integer vectors.
	alias Select!(isFloatingPoint!(T), T, float) DecimalType;	
	
	// To allow outside classes to access.
	alias T ElementType;
	alias N NumElements;
		static if(is(T == float) || is(T == double) || is(T == real)) {
			bool compareElement(size_t index, T value) const {
				return approxEqual(Elements[index], value);
			}
		} else {
			bool compareElement(size_t index, T value) const {
				return Elements[index] == value;
			}
		}

		unittest {
			static if(is(T == float) || is(T == double) || is(T == real)) {
				// TODO?
				/+Vector4f testVector = Vector4f(1.12f, 2.34f, 3.45f, 4.56f);
				assert(testVector.compareElement(0, 1.12f));
				assert(testVector.compareElement(1, 2.34f));
				assert(testVector.compareElement(2, testVector.Z));
				assert(testVector.compareElement(3, testVector.W));+/
			}
		}	

		T opIndex(size_t Index) const {
			return this.Elements[Index];
		}

		void opIndexAssign(size_t Index, T Value) {
			this.Elements[Index] = Value;
		}

		int opApply(int delegate(ref T) dg) {
			int Result;
			foreach(ref T Element; this.Elements)
				if((Result = dg(Element)) != 0)
					break;
			return Result;
		}

		/// Adds the specified vector to this vector, altering the values of this vector.
		/// Params: other = The other vector to use for this operation.
		void AddInline(ref Vector!(N, T) other) {
			version(Windows) {
				static if(N == 4 && is(T == float)) {	
					float* ptrA = &Elements[0];
					float* ptrB = &other.Elements[0];
					asm {				
						mov EAX, ptrA;
						mov EBX, ptrB;
						movups XMM0, [EAX];	
						movups XMM1, [EBX];
						addps XMM0, XMM1;
						movups [EAX], XMM0;
					}
					return;
				}
			}
			static if(N >= 2) {
				Elements[0] += other.Elements[0];	
				Elements[1] += other.Elements[1];
			} static if(N >= 3) {
				Elements[2] += other.Elements[2];	
			} static if(N >= 4) {
				Elements[3] += other.Elements[3];	
			} static if(N > 4) {
				for(size_t i = 4; i < N; i++)
					Elements[i] += other.Elements[i];
			}	
		}		

		static string GenOpInline(string Operation, string SimdOp) {
			// TODO: Aligned, check if stack alignment is fixed yet.
			// TODO: Optimize SIMD for non-floats.						
			static if(N == 4 && is(T == float) && IsWin32) {
				return "
					float* ptrA = &Elements[0];
					float* ptrB = &other.Elements[0];
					asm {							
						mov EAX, ptrA;
						mov EBX, ptrB;
						movups XMM0, [EAX];
						movups XMM1, [EBX];
						" ~ SimdOp ~ " XMM0, XMM1;
						movups [EAX], XMM0;
					}
				";									
			} else {
				// We do some manual loop unrolling here because DMD doesn't do it even for static arrays.
				return "
					static if(N >= 2) {						
						X " ~ Operation ~ "= other.X;
						Y " ~ Operation ~ "= other.Y;
					} static if(N >= 3) {
						Z " ~ Operation ~ "= other.Z;
					} static if(N >= 4) {
						W " ~ Operation ~ "= other.W;
					} static if(N > 4) {
						for(size_t i = 0; i < N; i++)
							Elements[i] " ~ Operation ~ "= other.Elements[i];
					}					
				";		
			}	
		}		
public:

	/// Initializes a nwe instance of the Vector structure.
	/// Params: Value = The value to initialize all elements to.
	this(T Value) {
		for(int i = 0; i < N; i++)
			this.Elements[i] = Value;
	}
	
	static if(N == 2) {
		/// Initializes a new instance of the Vector structure.			
		this(T X, T Y) {
			this.X = X;
			this.Y = Y;
		}
	} else static if(N == 3) {
		/// Initializes a new instance of the Vector structure.
		this(T X, T Y, T Z) {
			this.X = X;
			this.Y = Y;
			this.Z = Z;
		}
	} else static if(N == 4) {
		/// Initializes a new instance of the Vector structure.
		this(T X, T Y, T Z, T W) {
			this.X = X; 
			this.Y = Y;
			this.Z = Z; 
			this.W = W;
		}
	} else {
		/// Initializes a new instance of the Vector structure.
		this(const T[N] Elements...) {
			for(size_t i =0; i < Elements.length; i++)	
				this.Elements[i] = Elements[i];
		}
	}
	
	/// Overrides the splice operator.
	T[] opSlice() {
		return Elements;
	}
	
	/// Overrides the splice operator.
	T[] opSlice(size_t first, size_t last) {
		// TODO: Return a smaller Vector?
		return Elements[first .. last];	
	}
	
	/// Overrides the negation operator.	
	Vector!(N, T) opUnary(const string s)() if(s == "-") {
		Vector!(N, T) Result = void;
		for(size_t i = 0; i < N; i++)
			Result.Elements[i] = -Elements[i];		
		return Result;
	}
	
	/// Overrides the assignment operator.
	/// Params: other = The other vector to use for this operation.
	Vector!(N, T) opAssign(in Vector!(N, T) other) {		
		static if(N >= 2) {
			Elements[0] = other.Elements[0];	
			Elements[1] = other.Elements[1];
		} static if(N >= 3) {
			Elements[2] = other.Elements[2];	
		} static if(N >= 4) {
			Elements[3] = other.Elements[3];	
		} static if(N > 4) {
			for(size_t i = 4; i < N; i++)
				Elements[i] = other.Elements[i];
		}				
		return this;
	}

	string toString() const {
		string Result = "[";
		for(int i = 0; i < N; i++)
			Result ~= to!string(Elements[i]) ~ ", ";
		Result = Result[0..$-2] ~ "]";
		return Result;		
	}
	
	/// Returns the sum of this vector and the specified other vector.
	Vector opAdd(Vector other) const {				
		Vector!(N, T) Result = this;	
		Result.AddInline(other);
		return Result;		
	}

	Vector opAdd(T Scalar) {
		Vector!(N, T) Result = this;
		mixin(ScalarBinaryMixin("Result", "Scalar", "+"));
		return Result;
	}
	
	/// Implements the subtraction operator.
	Vector opSub(Vector other) const {
		Vector!(N, T) Result = this;
		Result.SubtractInline(other);
		return Result;
	}
	
	/// Implements the multiply operator.
	Vector opMul(Vector other) {
		Vector!(N, T) Result = this;
		Result.MultiplyInline(other);
		return Result;
	}

	Vector opMul(T scalar) {
		Vector!(N, T) Result = this;		
		mixin(ScalarBinaryMixin("Result", "scalar", "*"));
		return Result;
	}
	
	/// Implements the divide operator.
	Vector opDiv(Vector other) const {		
		Vector!(N, T) Result = this;			
		Result.DivideInline(other);
		return Result;
	}		

	Vector opBinary(string Op)(T Scalar) {
		Vector Result = this;
		mixin(ScalarBinaryMixin("Result", "Scalar", Op));
		return Result;
	}

	private static string ScalarBinaryMixin(string Left, string Right, string Op) {
		string Result = "";
		for(int i = 0; i < N; i++) {
			Result ~= Left ~ ".Elements[" ~ to!string(i) ~ "] " ~ Op ~ "= " ~ Right ~ "; "; 
		}
		return Result;
	}

	/// Implements the addition by assignment operator.
	void opAddAssign(Vector!(N, T) other) {
		AddInline(other);			
	}
	
	/// Implements the subtraction by assignment operator.
	void opSubtractAssign(Vector!(N, T) other) {
		SubtractInline(other);
	}
	
	/// Implements the multiplication by assignment operator.
	void opMultiplyAssign(Vector!(N, T) other) {
		MultiplyInline(other);
	}
	
	/// Implements the division by assignment operator.
	void opDivideAssign(Vector!(N, T) other) {
		DivideInline(other);
	}
	
	/// Multiplies this vector by the specified vector, altering the values of this vector.
	/// Params: other = The other vector to use for this operation.
	void MultiplyInline(ref Vector!(N, T) other) {		
		mixin(GenOpInline("*", "mulps"));
	}
	
	/// Divides this vector by the specified vector, altering the values of this vector.
	/// Params: other = The other vector to use for this operation.
	void DivideInline(ref Vector!(N, T) other) {
		mixin(GenOpInline("/", "divps"));
	}
	
	/// Subtracts the specified vector from this vector, altering the values of this vector.
	/// Params: other = The other vector to use for this operation.
	void SubtractInline(ref Vector!(N, T) other) {
		mixin(GenOpInline("-", "subps"));
	}		
	
	/// Returns the sum of all of the components in this Vector.
	T Sum() const {
		T Result = 0;
		foreach(Element; Elements)
			Result += Element;
		return Result;
	}
	
	/// Determines whether this vector is equal to the specified vector.
	/// Params: other = The other vector to use for this operation.
	bool Equals(const ref Vector!(N, T) other) const {
		for(size_t i = 0; i < N; i++)
			if(!compareElement(i, other.Elements[i]))
			   return false;
		return true;	
	}
	
	/// Overrides the equality operator.
	bool opEquals(const ref Vector!(N, T) other) const {
		return Equals(other);
	}

	/// Adds the specified vectors together, returning a new vector with the sum.
	/// Params:
	///		First = The first vector to use in the operation.
	///		Second = The second vector to use in the operation.
	/// Returns: A newly created Vector with the result of this operation.
	static Vector!(N, T) Add(ref Vector!(N, T) first, ref Vector!(N, T) second) {		
		Vector!(N, T) Result = first;
		Result.AddInline(second);
		return Result;		
	}
	
	/// Subtracts the second vector from the first vector, returning a new vector with the difference.
	/// Params:
	///		First = The first vector to use in the operation.
	///		Second = The second vector to use in the operation.
	/// Returns: A newly created Vector with the result of this operation.
	static Vector!(N, T) Subtract(ref Vector!(N, T) first, ref Vector!(N, T) second) {		
		Vector!(N, T) Result = first;
		Result.SubtractInline(second);
		return Result;	
	}
	
	/// Multiplies the specified vectors together, returning a new vector with the product.
	/// Params:
	///		First = The first vector to use in the operation.
	///		Second = The second vector to use in the operation.
	/// Returns: A newly created Vector with the result of this operation.
	static Vector!(N, T) Multiply(ref Vector!(N, T) first, ref Vector!(N, T) second) {		
		Vector!(N, T) Result = first;
		Result.MultiplyInline(second);
		return Result;	
	}	
	
	/// Divides the second vector from the first vector, returning a new vector with the quotient.
	/// Params:
	///		First = The first vector to use in the operation.
	///		Second = The second vector to use in the operation.
	/// Returns: A newly created Vector with the result of this operation.
	static Vector!(N, T) Divide(ref Vector!(N, T) first, ref Vector!(N, T) second) {		
		Vector!(N, T) Result = first;
		Result.DivideInline(second);
		return Result;	
	}
	
	/// Returns a new Vector with the minimum component of each Vector.
	static Vector!(N, T) Min(ref Vector!(N, T) first, ref Vector!(N, T) second) {
		//TODO: SIMD
		static if(N == 2)
			return Vector!(N, T)(cast(T)fmin(first.X, second.X), cast(T)fmin(first.Y, second.Y));
		else static if(N == 3)
			return Vector!(N, T)(cast(T)fmin(first.X, second.X), cast(T)fmin(first.Y, second.Y), cast(T)fmin(first.Z, second.Z));
		else static if(N == 4)
			return Vector!(N, T)(cast(T)fmin(first.X, second.X), cast(T)fmin(first.Y, second.Y), cast(T)fmin(first.Z, second.Z), cast(T)fmin(first.W, second.W));
		else {
			T[N] Elements;
			for(size_t i = 0; i < N; i++)
				Elements[i] = cast(T)fmin(first.Elements[i], second.Elements[i]);
		}
	}
	
	/// Returns a new Vector with the maximum component of each Vector.
	static Vector!(N, T) Max(ref Vector!(N, T) first, ref Vector!(N, T) second) {
		//TODO: SIMD
		static if(N == 2)
			return Vector!(N, T)(cast(T)fmax(first.X, second.X),cast(T) fmax(first.Y, second.Y));
		else static if(N == 3)
			return Vector!(N, T)(cast(T)fmax(first.X, second.X), cast(T)fmax(first.Y, second.Y), cast(T)fmax(first.Z, second.Z));
		else static if(N == 4)
			return Vector!(N, T)(cast(T)fmax(first.X, second.X), cast(T)fmax(first.Y, second.Y), cast(T)fmax(first.Z, second.Z), cast(T)fmax(first.W, second.W));
		else {
			T[N] Elements;
			for(size_t i = 0; i < N; i++)
				Elements[i] = cast(T)fmax(first.Elements[i], second.Elements[i]);
		}
	}
	
	/// Returns the distance between the two vectors squared.
	static T DistanceSquared(in Vector!(N, T) first, in Vector!(N, T) second) {
		static if(N <= 4) {
			static if(N >= 2) {
				T dX = first.X - second.X;
				T dY = first.Y - second.Y;
			} 
			static if(N >= 3)
				T dZ = first.Z - second.Z;
			static if(N >= 4)
				T dW = first.W - second.W;		
		}				
		static if(N == 2)
			return (dX * dX) +(dY * dY);
		else static if(N == 3)
			return (dX * dX) + (dY * dY) + (dZ * dZ);
		else static if(N == 4)
			return (dX * dX) + (dY * dY) + (dZ * dZ) + (dW * dW);
		else {
			T[N] Data;
			for(size_t i = 0; i < N; i++) {
				T dI = first.Elements[i] - second.Elements[i];
				Data[i] = dI * dI;				
			}
			return Vector!(N, T)(Data);
		}
	}
	
	/// Linearly interpolates between the first and second vector by the specified amount.
	/// Params: Amount = The amount to interpolate by. A value of 0 is entirely the first vector, with 1 being entirely the second vector.	
	static Vector!(N, T) Lerp(in Vector!(N, T) first, in Vector!(N, T) second, float Amount) {		
		static if(N <= 4) {
			static if(N >= 2) {
				T X = cast(T)(first.X + ((second.X - first.X) * Amount));
				T Y = cast(T)(first.Y + ((second.Y - first.Y) * Amount));
			}
			static if(N >= 3)
				T Z = cast(T)(first.Z + ((second.Z - first.Z) * Amount));
			static if(N >= 4)
				T W = cast(T)(first.W + ((second.W - first.W) * Amount));
			static if(N == 2)
				return Vector!(N, T)(X, Y);
			else static if(N == 3)
				return Vector!(N, T)(X, Y, Z);
			else
				return Vector!(N, T)(X, Y, Z, W);
		} else {
			T[N] Elements;
			for(size_t i = 0; i < N; i++)
				Elements[i] = cast(T)(first.Elements[i] + ((second.Elements[i] - first.Elements[i]) * Amount));
			return Vector!(N, T)(Elements);
		}
	}

	/// Gets the magnitude, or length, of this Vector.
	@property DecimalType Magnitude() const {		
		return cast(DecimalType)sqrt(cast(DecimalType)MagnitudeSquared);
	}

	/// Gets the Magnitude, or length, of this Vector without performing a square-root operation on the end result.
	@property T MagnitudeSquared() const {
		T Result = 0;
		foreach(ref Element; Elements) {
			static if(is(isIntegral!(T)))
				Result += Element << 1;
			else
				Result += Element * Element;
		}
		return Result;
	}

	/// Returns whether this Vector is normalized (aka, a unit vector).
	@property bool IsNormalized() const {
		return abs(MagnitudeSquared - 1) < 0.001;
	}
	
	/// Returns a normalized version of this Vector.
	Vector!(N, T) Normalize() const {		
		//TODO: SIMD
		static if(N <= 4) {
			static if(N >= 2) {
				DecimalType xS = X * X;
				DecimalType yS = Y * Y;
			} 
			static if(N >= 3)
				DecimalType zS = Z * Z;
			static if(N >= 4)
				DecimalType wS = W * W;
			static if(N == 2) { 
				auto Recip = sqrt(1 / (xS + yS));
				return Vector!(N, T)(cast(T)(X * Recip), cast(T)(Y * Recip));
			} else static if(N == 3) {
				auto Recip = sqrt(1 / (xS + yS + zS));
				return Vector!(N, T)(cast(T)(X * Recip), cast(T)(Y * Recip), cast(T)(Z * Recip));
			} else {
				auto Recip = sqrt(1 / (xS + yS + zS + wS));
				return Vector!(N, T)(cast(T)(X * Recip), cast(T)(Y * Recip), cast(T)(Z * Recip), cast(T)(W * Recip));
			}				
		} else {
			DecimalType Recip = 0;
			for(size_t i = 0; i < N; i++)
				Recip += Elements[i] * Elements[i];		
			Recip = sqrt(1 / Recip);
			T[N] Data;
			for(size_t i = 0; i < N; i++)
				Data = cast(T)(Elements[i] * Recip);
			return Vector!(N, T)(Data);
		}
	}
	
	/// Normalizes this Vector2 instance.
	void NormalizeInline() {
		static if(N <= 4) {
			static if(N >= 2) {
				DecimalType xS = X * X;
				DecimalType yS = Y * Y;
			} 
			static if(N >= 3) {
				DecimalType zS = Z * Z;
			} 
			static if(N == 4) {
				DecimalType wS = W * W;						
			} 
			static if(N == 2) { 
				auto Recip = sqrt(1 / (xS + yS));
				X *= Recip; 				
				Y *= Recip;				
			}  else static if(N == 3) {
				auto Recip = sqrt(1 / (xS + yS + zS));
				X *= Recip; 				
				Y *= Recip;				
				Z *= Recip;		
			} else static if(N == 4) {
				auto Recip = sqrt(1 / (xS + yS + zS + wS));
				X *= Recip; 				
				Y *= Recip;				
				Z *= Recip;		
				W *= Recip;				
			}				
		} else {
			DecimalType Recip = 0;			
			for(size_t i = 0; i < N; i++)
				Recip += Elements[i] * Elements[i];		
			Recip = sqrt(1 / Recip);
			T[N] Data;
			for(size_t i = 0; i < N; i++)
				Data = Elements[i] * Recip;
			return Vector!(N, T)(Data);
		}
	}
	
	/// Returns the dot product between the two vectors.
	static T Dot(ref Vector!(N, T) first, ref Vector!(N, T) second) {		
		//TODO: SIMD
		static if(N <= 4) {
			static if(N >= 2) {
				T X = first.X * second.X;
				T Y = first.Y * second.Y;
				
			}
			static if(N >= 3)
				T Z = first.Z * second.Z;
			static if(N >= 4)
				T W = first.W * second.W;
			static if(N == 2)
				return X + Y;
			else static if(N == 3)
				return X + Y + Z;
			else static if(N == 4)
				return X + Y + Z + W;
		} else {
			T Sum = 0;
			for(size_t i = 0; i < N; i++)
				Sum += first.Elements[i] * second.Elements[i];
		}
	}
	
	static if(N == 3) {
		/// Returns the cross product between the two vectors. Only valid when N is equal to 3.
		/// Params:
		/// 	First = The first vector to use.
		/// 	Second = The second vector to use.
		static Vector!(N, T) Cross(const ref Vector!(N, T) First, const ref Vector!(N, T) Second) {
			return Vector!(N, T)(
				First.Y * Second.Z - Second.Y * First.Z, 
				First.Z * Second.X - Second.Z * First.X,
				First.X * Second.Y - Second.X * First.Y
			);
		}		
	}
	
	///	Determines whether this Vector contains an element with the specified value.
	bool Contains(T Value) const {	
		for(size_t i = 0; i < N; i++)
			if(compareElement(i, Value))
				return true;				
		return false;
	}
	
	//static if(((N * T.sizeof) % 16) == 0) {
		//align(16):
		//private enum bool UseAlignedSSE = true;
	//} else
		private enum bool UseAlignedSSE = false;
			
	// Union for X/Y/Z/W.
	static if(N == 2) {
		union {
			struct { T X, Y; };			
			T[2] Elements;	
		}
	} else static if(N == 3) {
		union {
			struct { T X, Y, Z; };			
			T[3] Elements;
		}
	} else static if(N == 4) {
		union {
			T[4] Elements;
			struct { T X, Y, Z, W; };			
		}
	} else {		
		T[N] Elements;	
	}	
	
}

unittest {
	Vector4f first4f = Vector4f(1, 2, 3, 4);	
	Vector4f second4f = Vector4f(2, 3, 4, 5);
	//assert((first4f + second4f) == Vector4f(3, 5, 7, 9));	
	//assert((first4f * second4f) == Vector4f(2, 6, 12, 20));
	//assert((first4f / second4f) == Vector4f((1 / 2f), (2 / 3f), (3 / 4f), (4 / 5f)));
	//assert((first4f - second4f) == Vector4f(-1, -1, -1, -1));		   
}

alias Vector!(4, float) Vector4f;
alias Vector!(4, double) Vector4d;
alias Vector!(4, int) Vector4i;
alias Vector!(4, size_t) Vector4t;
alias Vector!(4, ptrdiff_t) Vector4p;
//alias Vector!(4, bool) Vector4b;

alias Vector!(3, float) Vector3f;
alias Vector!(3, double) Vector3d;
alias Vector!(3, int) Vector3i;
alias Vector!(3, size_t) Vector3t;
alias Vector!(3, ptrdiff_t) Vector3p;
//alias Vector!(3, bool) Vector3b;

alias Vector!(2, float) Vector2f;
alias Vector!(2, double) Vector2d;
alias Vector!(2, int) Vector2i;
alias Vector!(2, size_t) Vector2t;
alias Vector!(2, ptrdiff_t) Vector2p;
//alias Vector!(2, bool) Vector2b;

version(Windows)
	enum bool IsWin32 = true;
else
	enum bool IsWin32 = false;
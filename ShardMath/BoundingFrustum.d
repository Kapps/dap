module ShardMath.BoundingFrustum;
import ShardMath.Matrix;
import ShardMath.Vector;
import ShardMath.BoundingBox;

/// Determines how an object overlaps another.
enum Overlaps {
	/// The objects do not overlap.
	None = 0,
	/// The objects intersect each other.
	Partially = 1,
	/// The first object fully contains the second.
	Fully = 2
}

/// Represents a frustum in 3D space, generally used for view culling.
class BoundingFrustum  {

public:	

	/// Initializes a new instance of the BoundingFrustum object.
	/// Params:
	///		Matrix = The world matrix multiplied by the view matrix multiplied by the projection matrix.
	this(Matrix4f WorldViewProj) {
		this._Matrix = WorldViewProj;
	}

	/// Determines whether this BoundingFrustum contains the given object.
	/// Params:
	/// 	Object = The object to check for containment.
	Overlaps Overlap(BoundingBox Object) {
		return Overlaps.Fully; // TODO: Implement.
	}

	/// Ditto
	Overlaps Overlap(Vector3f Point) {
		return Overlaps.Fully; // TODO: Implement.
	}

	/// Gets or sets the matrix used for this BoundingFrustum. This is generally the view matrix multiplied by the projection matrix.
	@property Matrix4f Matrix() const {
		return _Matrix;
	}

	/// Ditto
	@property void Matrix(Matrix4f Value) {
		this._Matrix = Value;
	}
	
private:
	Matrix4f _Matrix;
}
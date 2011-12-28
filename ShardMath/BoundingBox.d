module ShardMath.BoundingBox;
import ShardMath.Vector;

/// Determines the type of containment between two objects, with values being arranged by most containment (fully), to least containment (disjoint).
enum ContainmentType {
	Disjoint,
	Intersects,
	Contains
}

/// Represents a 3D Axis-Aligned Bounding Box (AABB).
struct BoundingBox  {

public:
	/// The minimum coorindates for this box.
	Vector3f Min;
	/// The maximum coordinates for this box.
	Vector3f Max;

	/// Creates a BoundingBox with the given coordinates.
	/// Params:
	/// 	Min = The minimum coordinates for this BoundingBox.
	/// 	Max = The maximum coordinates for this BoundingBox.
	this(Vector3f Min, Vector3f Max) {
		this.Min = Min;
		this.Max = Max;
	}
	
	/// Checks whether the two BoundingBoxes collide with each other.
	/// Params:
	/// 	Other = The other BoundingBox to check for collision.
	bool Intersects(BoundingBox Other) const {
		if(Max.X < Other.Min.X || Min.X > Other.Max.X)
			return false;
		if(Max.Y < Other.Min.Y || Min.Y > Other.Max.Y)
			return false;
		return Max.Z >= Other.Min.Z && Min.Z <= Other.Max.Z;
	}

	/// Determines how the two BoundingBoxes are contained within each other.
	/// Params:
	/// 	Other = The other BoundingBox to check for collision.
	ContainmentType Contains(BoundingBox Other) {
		if(Max.X < Other.Min.X || Min.X > Other.Max.X)
			return ContainmentType.Disjoint;
		if(Max.Y < Other.Min.Y || Min.Y > Other.Max.Y)
			return ContainmentType.Disjoint;
		if(Max.Z < Other.Min.Z || Min.Z > Other.Max.Z)
			return ContainmentType.Disjoint;
		if(Min.X <= Other.Min.X && Max.X >= Other.Max.X && Min.Y <= Other.Min.Y && Max.Y >= Other.Max.Y && Min.Z <= Other.Min.Z && Max.Z >= Other.Max.Z)
			return ContainmentType.Contains;
		return ContainmentType.Intersects;
	}

	bool opEquals(const ref BoundingBox Other) const {
		return Min == Other.Min && Max == Other.Max;
	}

private:
	
	unittest {
		BoundingBox first = BoundingBox(Vector3f(0.33, 0.33, 0.33), Vector3f(1, 1, 1));
		BoundingBox firstEqual = first;
		BoundingBox second = BoundingBox(Vector3f(0, 0, 0), Vector3f(2, 2, 2));
		BoundingBox third = BoundingBox(Vector3f(0, 0, 0), Vector3f(1, 1, 1));

		//assert(first == firstEqual);
		assert(first.Intersects(second));
		assert(second.Intersects(first));
		assert(second.Contains(first) == ContainmentType.Contains);
		assert(second.Contains(third) == ContainmentType.Contains);
		assert(third.Contains(second) == ContainmentType.Intersects);
		assert(first.Contains(second) == ContainmentType.Intersects);
	}
	
}
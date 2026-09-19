package com.example.mooddare

import com.google.mlkit.vision.facemesh.FaceMesh

internal object MeshGeometryFactory {
    fun matching(meshes: List<FaceMesh>, face: FloatArray, width: Int, height: Int): FaceGeometry? =
        meshes.mapNotNull { mesh ->
            fun contour(type: Int) = mesh.getPoints(type).flatMap {
                listOf(it.position.x / width, it.position.y / height)
            }.toFloatArray()
            fun joined(a: Int, b: Int) = FaceGeometry.join(contour(a), contour(b))
            FaceGeometry.create(listOf(
                contour(FaceMesh.FACE_OVAL), contour(FaceMesh.LEFT_EYE), contour(FaceMesh.RIGHT_EYE),
                joined(FaceMesh.LEFT_EYEBROW_TOP, FaceMesh.LEFT_EYEBROW_BOTTOM),
                joined(FaceMesh.RIGHT_EYEBROW_TOP, FaceMesh.RIGHT_EYEBROW_BOTTOM),
                joined(FaceMesh.UPPER_LIP_TOP, FaceMesh.LOWER_LIP_BOTTOM),
                joined(FaceMesh.UPPER_LIP_BOTTOM, FaceMesh.LOWER_LIP_TOP)
            ))
        }.filter { it.matches(face) }.singleOrNull()
}

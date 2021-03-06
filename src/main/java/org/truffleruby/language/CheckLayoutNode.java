/*
 * Copyright (c) 2016, 2017 Oracle and/or its affiliates. All rights reserved. This
 * code is released under a tri EPL/GPL/LGPL license. You can use it,
 * redistribute it and/or modify it under the terms of the:
 *
 * Eclipse Public License version 1.0, or
 * GNU General Public License version 2, or
 * GNU Lesser General Public License version 2.1.
 */
package org.truffleruby.language;

import com.oracle.truffle.api.dsl.Cached;
import com.oracle.truffle.api.dsl.ImportStatic;
import com.oracle.truffle.api.dsl.NodeChild;
import com.oracle.truffle.api.dsl.Specialization;
import com.oracle.truffle.api.object.DynamicObject;
import com.oracle.truffle.api.object.ObjectType;
import com.oracle.truffle.api.object.Shape;
import org.truffleruby.Layouts;
import org.truffleruby.language.CheckLayoutNodeFactory.GetObjectTypeNodeGen;
import org.truffleruby.language.objects.ShapeCachingGuards;

public class CheckLayoutNode extends RubyBaseNode {

    @Child private GetObjectTypeNode getObjectTypeNode = GetObjectTypeNodeGen.create(null);

    public boolean isString(DynamicObject object) {
        return Layouts.STRING.isString(getObjectTypeNode.executeGetObjectType(object));
    }

    @NodeChild("object")
    @ImportStatic(ShapeCachingGuards.class)
    public static abstract class GetObjectTypeNode extends RubyNode {

        public abstract ObjectType executeGetObjectType(DynamicObject object);

        @Specialization(
                guards = "object.getShape() == cachedShape",
                limit = "getLimit()")
        ObjectType cachedShapeGetObjectType(DynamicObject object,
                @Cached("object.getShape()") Shape cachedShape) {
            return cachedShape.getObjectType();
        }

        @Specialization(guards = "updateShape(object)")
        ObjectType updateShapeAndRetry(DynamicObject object) {
            return executeGetObjectType(object);
        }

        @Specialization(replaces = { "cachedShapeGetObjectType", "updateShapeAndRetry" })
        ObjectType uncachedGetObjectType(DynamicObject object) {
            return object.getShape().getObjectType();
        }

        protected int getLimit() {
            return getContext().getOptions().IS_A_CACHE;
        }

    }

}

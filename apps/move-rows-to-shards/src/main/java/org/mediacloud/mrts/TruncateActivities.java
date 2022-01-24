package org.mediacloud.mrts;

import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

import javax.annotation.Nullable;

@ActivityInterface
public interface TruncateActivities {

    @ActivityMethod
    void truncateIfEmpty(String table);
}

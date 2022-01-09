package org.mediacloud.mrts;

import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

import javax.annotation.Nullable;

@ActivityInterface
public interface MinMaxTruncateActivities {

    @ActivityMethod
    @Nullable
    Long minColumnValue(String table, String idColumn);

    @ActivityMethod
    @Nullable
    Long maxColumnValue(String table, String idColumn);

    @ActivityMethod
    void truncateIfEmpty(String table);

    @ActivityMethod
    void noOp(String table);
}

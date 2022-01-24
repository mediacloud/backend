package org.mediacloud.mrts;

import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

import java.util.List;

@ActivityInterface
public interface MoveRowsActivities {
    @ActivityMethod
    void runQueriesInTransaction(List<String> sqlQueries);
}

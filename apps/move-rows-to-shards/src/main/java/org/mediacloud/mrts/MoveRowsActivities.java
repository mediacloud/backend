package org.mediacloud.mrts;

import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

import java.util.List;

@ActivityInterface
public interface MoveRowsActivities {
    @ActivityMethod
    String runQueriesInTransaction(List<String> sqlQueries);
}

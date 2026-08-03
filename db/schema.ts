import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const workbenchSync = sqliteTable("workbench_sync", {
  userId: text("user_id").primaryKey(),
  payload: text("payload").notNull(),
  updatedAt: integer("updated_at").notNull(),
});

PRAGMA foreign_keys = ON;

CREATE TABLE foods (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  source TEXT NOT NULL,
  emoji TEXT NULL,
  thumbnail TEXT NULL,
  caloriesPerGram REAL NOT NULL,
  proteinPerGram REAL NOT NULL,
  fatPerGram REAL NOT NULL,
  carbsPerGram REAL NOT NULL,
  fiberPerGram REAL NOT NULL,
  sourceFdcId INTEGER NULL,
  sourceBarcode TEXT NULL,
  usageNote TEXT NULL,
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1)),
  parentId INTEGER NULL REFERENCES foods (id)
);

CREATE TABLE food_portions (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  foodId INTEGER NOT NULL REFERENCES foods (id),
  unitName TEXT NOT NULL,
  gramsPerPortion REAL NOT NULL,
  quantityPerPortion REAL NOT NULL
);

CREATE TABLE recipes (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  emoji TEXT NULL,
  thumbnail TEXT NULL,
  servings_created REAL NOT NULL DEFAULT 1.0,
  final_weight_grams REAL NULL,
  portion_name TEXT NOT NULL DEFAULT 'portion',
  notes TEXT NULL,
  is_template INTEGER NOT NULL DEFAULT 0 CHECK (is_template IN (0, 1)),
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1)),
  parent_id INTEGER NULL REFERENCES recipes (id),
  created_timestamp INTEGER NOT NULL
);

CREATE TABLE categories (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE recipe_category_links (
  recipe_id INTEGER NOT NULL REFERENCES recipes (id),
  category_id INTEGER NOT NULL REFERENCES categories (id),
  UNIQUE (recipe_id, category_id)
);

CREATE TABLE recipe_items (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  recipe_id INTEGER NOT NULL REFERENCES recipes (id),
  ingredient_food_id INTEGER NULL REFERENCES foods (id),
  ingredient_recipe_id INTEGER NULL REFERENCES recipes (id),
  grams REAL NOT NULL,
  unit TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE logged_portions (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  loggedFoodId INTEGER NULL REFERENCES foods (id),
  recipeId INTEGER NULL REFERENCES recipes (id),
  log_timestamp INTEGER NOT NULL,
  grams REAL NOT NULL,
  unit TEXT NOT NULL,
  quantity REAL NOT NULL
);

CREATE TABLE weights (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  weight REAL NOT NULL,
  date INTEGER NOT NULL
);

CREATE TABLE containers (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  weight REAL NOT NULL,
  unit TEXT NOT NULL DEFAULT 'g',
  thumbnail TEXT NULL,
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1))
);

CREATE TABLE food_barcodes (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  food_id INTEGER NOT NULL REFERENCES foods (id) ON DELETE CASCADE,
  barcode TEXT NOT NULL,
  UNIQUE (food_id, barcode)
);

INSERT INTO foods (
  id, name, source, emoji, thumbnail, caloriesPerGram, proteinPerGram,
  fatPerGram, carbsPerGram, fiberPerGram, sourceFdcId, sourceBarcode,
  usageNote, hidden, parentId
) VALUES
  (1, 'Historical oats', 'user', '🥣', 'local:food-image', 3.8, 0.13, 0.07, 0.68, 0.10, NULL, NULL, 'original snapshot', 1, NULL),
  (2, 'Current oats', 'user', '🥣', 'local:food-image-current', 4.2, 0.15, 0.08, 0.70, 0.09, NULL, NULL, 'current version', 0, 1);

INSERT INTO food_portions (id, foodId, unitName, gramsPerPortion, quantityPerPortion)
VALUES (1, 1, 'bowl', 80.0, 1.0), (2, 2, 'bowl', 85.0, 1.0);

INSERT INTO recipes (
  id, name, emoji, thumbnail, servings_created, final_weight_grams,
  portion_name, notes, is_template, hidden, parent_id, created_timestamp
) VALUES
  (10, 'Oat bowl', '🥣', 'local:recipe-image', 2.0, 500.0, 'bowl', 'fixture recipe', 0, 0, NULL, 1735689600000),
  (11, 'Oat bowl plan', '📋', NULL, 1.0, NULL, 'portion', NULL, 1, 0, NULL, 1735776000000);

INSERT INTO categories (id, name) VALUES (20, 'Breakfast');
INSERT INTO recipe_category_links (recipe_id, category_id) VALUES (10, 20);
INSERT INTO recipe_items (id, recipe_id, ingredient_food_id, ingredient_recipe_id, grams, unit, position)
VALUES
  (30, 10, 1, NULL, 80.0, 'bowl', 0),
  (31, 11, NULL, 10, 250.0, 'bowl', 0);

INSERT INTO logged_portions (id, loggedFoodId, recipeId, log_timestamp, grams, unit, quantity)
VALUES
  (40, 1, NULL, 1735862400000, 80.0, 'bowl', 1.0),
  (41, NULL, 10, 1735948800000, 250.0, 'bowl', 1.0);

INSERT INTO weights (id, weight, date) VALUES (50, 81.25, 1735862400000);
INSERT INTO containers (id, name, weight, unit, thumbnail, hidden)
VALUES (60, 'Glass bowl', 420.0, 'g', 'local:container-image', 0);
INSERT INTO food_barcodes (id, food_id, barcode) VALUES (70, 2, '0123456789012');

PRAGMA user_version = 13;

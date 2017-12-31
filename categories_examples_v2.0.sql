-- --------------------------------------------------------------------------
-- create a category tree, there can be many
-- --------------------------------------------------------------------------
insert into category_tree values (1, 'Main Tree', 'The main category tree', 
  now(), now());

-- --------------------------------------------------------------------------
-- adds a root category to a category tree, root category is 0
-- --------------------------------------------------------------------------
call addChildCategory(0, categoryTreeId, 'categoryName', 'categoryDescription', 
  isAlias, aliasId, prependToCategory, outputCategoryId);

-- --------------------------------------------------------------------------
-- adds a category to a parent category in a category tree
-- --------------------------------------------------------------------------
call addChildCategory(parentCategoryId, categoryTreeId, categoryName, 
  categoryDescription, isAlias, aliasId, prependToCategory, outputCategoryId);

-- --------------------------------------------------------------------------
-- adds a sibling category before a category in a category tree, prepend true
-- --------------------------------------------------------------------------
call addSiblingCategory(siblingId, categoryTreeId, categoryName, 
  categoryDescription, isAlias, aliasId, true, outputCategoryId);

-- --------------------------------------------------------------------------
-- adds a sibling category after a category in a category tree, prepend false
-- --------------------------------------------------------------------------
call addSiblingCategory(siblingId, categoryTreeId, categoryName, 
  categoryDescription, isAlias, aliasId, false, outputCategoryId);

-- --------------------------------------------------------------------------
-- removes a category from a tree
-- --------------------------------------------------------------------------
call removeCategory(categoryId, deleteChildren);

-- --------------------------------------------------------------------------
-- move a category tree and its children to a different parent
-- --------------------------------------------------------------------------
call moveToChildOfCategory(categoryId, categoryTreeId, moveToParentId, prepend);

-- --------------------------------------------------------------------------
-- move a category tree and its children as a sibling of a different category
-- --------------------------------------------------------------------------
call moveToSiblingOfCategory(categoryId, categoryTreeId, moveToSiblingId, 
  prepend);

-- --------------------------------------------------------------------------
-- get category
-- --------------------------------------------------------------------------
select        *
from          categories
where         category_id = 1;

-- --------------------------------------------------------------------------
-- get all categories
-- --------------------------------------------------------------------------
select        *
from          categories
order by      lft;

-- --------------------------------------------------------------------------
-- get all categories for tree
-- --------------------------------------------------------------------------
select        *
from          categories
where         category_tree_id = 1
order by      lft;


-- --------------------------------------------------------------------------
-- get single category path
-- --------------------------------------------------------------------------
select        p.*
from          categories n
join          categories p
where         n.lft between p.lft and p.rgt
and           n.category_id = 1
and           p.category_tree_id = 1
order by      p.lft;

-- --------------------------------------------------------------------------
-- get first child
-- --------------------------------------------------------------------------
select        *
from          categories
where         parent_id = 1
and           lft = (
  select lft from categories where category_id = 1) + 1;

-- --------------------------------------------------------------------------
-- get last child
-- --------------------------------------------------------------------------
select        *
from          categories
where         parent_id = 1
and           rgt = (
  select rgt from categories where category_id = 1) - 1;

-- --------------------------------------------------------------------------
-- get immediate children
-- --------------------------------------------------------------------------
select        *
from          categories
where         parent_id = 1
order by      lft;

-- --------------------------------------------------------------------------
-- get count immediate children
-- --------------------------------------------------------------------------
select        count(*)
from          categories
where         parent_id = 1
and           category_tree_id = 1
order by      lft;

-- --------------------------------------------------------------------------
-- get subtree
-- --------------------------------------------------------------------------
select        c.*
from          categories c
where         lft > (select lft from categories where category_id = 1)
and           rgt < (select rgt from categories where category_id = 1)
and           category_tree_id = 1
order by      lft;

-- --------------------------------------------------------------------------
-- get count subtree
-- --------------------------------------------------------------------------
select        count(*)
from          categories c
where         lft > (select lft from categories where category_id = 1)
and           rgt < (select rgt from categories where category_id = 1)
and           category_tree_id = 1
order by      lft;
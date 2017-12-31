-- -----------------------------------------------------------------------------
-- Name: categories_v2.0.sql
-- Description: This script creates the schema for the categories database.
-- Authors: Dennis E. Kubes
--
-- Version      Date                  Comments
-- -----------------------------------------------------------------------------
-- 2.0          July 26, 2012         Initial script creation.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- create database and user
-- -----------------------------------------------------------------------------
drop database if exists cats;
create database cats;

drop user catdba;
grant all privileges on cats.* 
to 'catdba'@'%' identified by 'password'
with grant option;

grant select on mysql.proc to 'catdba'@'%';

use cats;

-- --------------------------------------------------------------------------
-- drop functions, and procedures
-- --------------------------------------------------------------------------
drop function if exists getParentCategoryName;
drop function if exists getCategoryByTreeFullName;
drop function if exists getParentCategoryByTreeFullName;
drop function if exists getCategoryName;
drop function if exists getFullCategoryName;
drop procedure if exists addChildCategory;
drop procedure if exists addChildCategoryByFullName;
drop procedure if exists addSiblingCategory;
drop procedure if exists removeCategory;
drop procedure if exists moveToChildOfCategory;
drop procedure if exists moveToSiblingOfCategory;
drop procedure if exists updateCategory;

-- -----------------------------------------------------------------------------
-- drop existing tables
-- -----------------------------------------------------------------------------
drop table if exists category;
drop table if exists category_tree;

-- -----------------------------------------------------------------------------
-- category tables
-- -----------------------------------------------------------------------------
create table category_tree (
  category_tree_id bigint unsigned not null auto_increment,
  name varchar(100) not null,
  description varchar(250),      
  created datetime not null,
  updated datetime not null,
  constraint primary key (category_tree_id),   
  constraint uc01_category_tree unique (name),  
  index idx01_category_tree (name)
) engine = innodb;
-- -----------------------------------------------------------------------------
create table category (
  category_id bigint unsigned not null auto_increment,
  category_tree_id bigint unsigned not null,
  parent_id bigint unsigned not null default 0,
  name varchar(100) not null,
  fullname text not null,
  description text,
  lft int unsigned not null,
  rgt int unsigned not null,
  node_depth int unsigned not null,
  is_alias boolean not null default false,
  alias_id bigint unsigned,
  constraint primary key (category_id),
  constraint uc01_category unique (parent_id, name),  
  constraint fk01_category
    foreign key idx01_category (category_tree_id)
    references category_tree (category_tree_id),  
  index idx01_category (category_tree_id), 
  index idx02_category (parent_id),
  index idx03_category (name), 
  index idx04_category (lft),
  index idx05_category (rgt),    
  index idx06_category (node_depth),
  index idx07_category (alias_id)
) engine = innodb;

-- -----------------------------------------------------------------------------
-- get parent category name
-- -----------------------------------------------------------------------------
drop function if exists getParentCategoryName;
delimiter $$
create function getParentCategoryName(
  fullCategoryName varchar(250)
)
returns text
deterministic
reads sql data
begin

  declare tempCatName varchar(250) default '';
  set tempCatName = trim(fullCategoryName);

  if (right(tempCatName, 1) = '/') then
    set tempCatName = substr(tempCatName, 1, length(tempCatName) - 1);
  end if;
  
  if (instr(tempCatName, '/') > 0) then
    return substr(tempCatName, 1, 
      (length(tempCatName) - length(substring_index(tempCatName, '/', -1))) - 1);
  else 
    return null;    
  end if;

end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- get category by tree and fullname
-- -----------------------------------------------------------------------------
drop function if exists getCategoryByTreeFullName;
delimiter $$
create function getCategoryByTreeFullName(
  categoryTreeId int,
  fullCategoryName varchar(250)
)
returns int
deterministic
reads sql data
begin

  declare catId int default 0;

  select    category_id
  into      catId
  from      category
  where     category_tree_id = categoryTreeId
  and       fullname = trim(fullCategoryName)
  limit     1;

  -- return the category id
  return catId;

end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- get parent category by tree and fullname
-- -----------------------------------------------------------------------------
drop function if exists getParentCategoryByTreeFullName;
delimiter $$
create function getParentCategoryByTreeFullName(
  categoryTreeId int,
  fullCategoryName varchar(250)
)
returns int
deterministic
reads sql data
begin

  declare tempCatName varchar(250) default '';
  set tempCatName = getParentCategoryName(trim(fullCategoryName));
  
  if (tempCatName is not null) then
    return getCategoryByTreeFullName(categoryTreeId, tempCatName);
  else
    return 0;
  end if;

end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- get category name
-- -----------------------------------------------------------------------------
drop function if exists getCategoryName;
delimiter $$
create function getCategoryName(
  fullCategoryName varchar(250)
)
returns text
deterministic
reads sql data
begin

  declare tempCatName varchar(250) default '';
  set tempCatName = trim(fullCategoryName);

  if (right(tempCatName, 1) = '/') then
    set tempCatName = substr(tempCatName, 1, length(tempCatName) - 1);
  end if;
  
  if (instr(tempCatName, '/') > 0) then
    return substring_index(tempCatName, '/', -1);
  else 
    return tempCatName;
  end if;

end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- get full name function
-- -----------------------------------------------------------------------------
drop function if exists getFullCategoryName;
delimiter $$
create function getFullCategoryName(
  parentId int, 
  categoryName varchar(250)
)
returns text
deterministic
reads sql data
begin

  declare fullCategoryName text default '';

  -- get the parent category name, or null if no parent category
  if (parentId > 0) then

    select    fullname
    into      fullCategoryName
    from      category
    where     category_id = parentId
    limit     1;

    -- concat the parent category name with a separator and the current name
    return concat(fullCategoryName, '/', trim(categoryName));

  end if;

  return categoryName;

end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- add child category procedure
-- -----------------------------------------------------------------------------
drop procedure if exists addChildCategory;
delimiter $$
create procedure addChildCategory(
  in parentId int, 
  in categoryTreeId int,
  in categoryName varchar(50), 
  in categoryDesc varchar(100),
  in isAlias boolean,
  in aliasId int,
  in prepend boolean,
  out newCatId int
)
begin
  
  declare catId int default -1;
  declare parentLeft int default 0;
  declare parentRight int default 0;
  declare posLeft int default 0;
  declare posRight int default 0;
  declare maxRight int default 0;
  declare parentNodeDepth int default 0;
  declare nodeDepth int default 0;
  declare fullName varchar(250) default '';
  
  -- get the left, right, and node depth for the parent category we are 
  -- adding a child too, if <= 0 then adding to root
  if (parentId is not null and parentId > 0) then
    select        lft, rgt, node_depth
    into          parentLeft, parentRight, parentNodeDepth
    from          category
    where         category_id = parentId;
  end if;
  
  -- get the full category name and set the node depth for the new category
  set fullName = getFullCategoryName(parentId, categoryName);  
  set nodeDepth = parentNodeDepth + 1;

  -- if we are prepending or appending inside the parent category children
  if (prepend) then

    -- if prepending, set the left and right positions of the new category
    -- before we update, and update the tree with new positions pushed down 2
    set posLeft = parentLeft + 1;
    set posRight = parentLeft + 2;
    update category set lft = (lft + 2) where lft > parentLeft
      and category_tree_id = categoryTreeId;    
    update category set rgt = (rgt + 2) where rgt >= parentRight
      and category_tree_id = categoryTreeId;  

  else
    
    -- if adding to root and appending get the max root child which is max
    -- right of the tree and 
    if (parentLeft = 0 and parentRight = 0) then

      select          ifnull(max(rgt), 0)
      into            maxRight
      from            category
      where           category_tree_id = categoryTreeId;

      set posLeft = maxRight + 1;
      set posRight = maxRight + 2;

    else

      -- set right and left before update, then update any push down by 2 any
      -- part of the tree after the parent
      set posLeft = parentRight;
      set posRight = parentRight + 1;
      update category set lft = (lft + 2) where lft > parentRight
        and category_tree_id = categoryTreeId;  
      update category set rgt = (rgt + 2) where rgt >= parentRight
        and category_tree_id = categoryTreeId;  

    end if;

  end if;

  -- insert the new category and return the category id
  insert into     category
                  (category_tree_id, parent_id, name, fullname, description, lft, 
                   rgt, node_depth, is_alias, alias_id)
  values          (categoryTreeId, parentId, categoryName, fullName, categoryDesc, 
                  posLeft, posRight, nodeDepth, isAlias, aliasId);
  select last_insert_id() into newCatId;
                
end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- add child category by tree and full category name procedure
-- -----------------------------------------------------------------------------
drop procedure if exists addChildCategoryByFullName;
delimiter $$
create procedure addChildCategoryByFullName(
  in categoryTreeId int,
  in fullCategoryName varchar(250), 
  in categoryDesc varchar(250),
  in isAlias boolean,
  in aliasId int,
  in prepend boolean,
  out newCatId int
)
begin
  
  declare catId int default -1;
  declare parentCatId int default 0;
  declare tempCatName varchar(250) default '';
  
  set parentCatId = getParentCategoryByTreeFullName(categoryTreeId, 
    trim(fullCategoryName));
  set tempCatName = getCategoryName(trim(fullCategoryName));    
  call addChildCategory(parentCatId, categoryTreeId, tempCatName, 
    categoryDesc, isAlias, aliasId, prepend, newCatId);  
                
end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- add sibling category procedure
-- -----------------------------------------------------------------------------
drop procedure if exists addSiblingCategory;
delimiter $$
create procedure addSiblingCategory(
  in siblingId int, 
  in categoryTreeId int,
  in categoryName varchar(50), 
  in categoryDesc varchar(100),
  in isAlias boolean,
  in aliasId int,
  in prepend boolean,
  out newCatId int
)
proc: begin
  
  declare catId int default 0;
  declare sibLeft int default 0;
  declare sibRight int default 0;
  declare sibParentid int default 0;
  declare posLeft int default 1;
  declare posRight int default 2;
  declare maxRight int default 0;
  declare sibNodeDepth int default 0;
  declare nodeDepth int default 0;
  declare fullName varchar(250) default '';

  -- get the left, right, and node depth for the sibling category we are 
  -- adding a near, if <= 0 then adding to root
  if (siblingId is null or siblingId <= 0) then
    leave proc;
  else
    select        lft, rgt, node_depth, parent_id
    into          sibLeft, sibRight, sibNodeDepth, sibParentId
    from          category
    where         category_id = siblingId;
  end if;

  -- get the full category name and set the node depth for the new category
  set fullName = getFullCategoryName(sibParentId, categoryName);  
  set nodeDepth = sibNodeDepth;

  -- if we are prepending or appending to the sibling category
  if (prepend) then

    -- if prepending, set the left and right positions of the new category
    -- before we update, and update the tree with new positions pushed down 2
    if (sibLeft > 0 and sibRight > 0) then
      set posLeft = sibLeft;
      set posRight = sibLeft + 1;
    end if;

    update category set lft = (lft + 2) where lft >= sibLeft
      and category_tree_id = categoryTreeId;   
    update category set rgt = (rgt + 2) where rgt >= sibLeft
      and category_tree_id = categoryTreeId;  

  else

    -- if appending, set the left and right positions and push tree after the 
    -- sibling down by 2
    if (sibLeft > 0 and sibRight > 0) then
      set posLeft = sibRight + 1;
      set posRight = sibRight + 2;
    end if;

    update category set lft = (lft + 2) where lft > sibRight
      and category_tree_id = categoryTreeId;    
    update category set rgt = (rgt + 2) where rgt > sibRight
      and category_tree_id = categoryTreeId;  

  end if;

  -- insert the new category and return the category id
  insert into     category
                  (category_tree_id, parent_id, name, fullname, description, lft, 
                   rgt, node_depth, is_alias, alias_id)
  values          (categoryTreeId, sibParentId, categoryName, fullName, 
                  categoryDesc, posLeft, posRight, nodeDepth, isAlias, aliasId);
  select last_insert_id() into newCatId;
                
end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- remove category procedure
-- -----------------------------------------------------------------------------
drop procedure if exists removeCategory;
delimiter $$
create procedure removeCategory(
  in categoryId int,
  in deleteChildren boolean
)
proc: begin
  
  declare leftPos int default 0;
  declare rightPos int default 0;
  declare nodeWidth int default 0;
  declare parentId int default 0;
  declare catName varchar(50) default '';
  declare catTreeId int default 0;

  if (categoryId is null or categoryId <= 0) then
    leave proc;
  end if;
  
  -- get the variables for the category to delete
  select      lft, rgt, (rgt - lft) + 1, category_tree_id, parent_id, name
  into        leftPos, rightPos, nodeWidth, catTreeId, parentId, catName
  from        category
  where       category_id = categoryId;
  
  -- delete the category from the tree
  delete from category where category_id = categoryId
    and category_tree_id = catTreeId;
  
  -- deleting child categories or not
  if (deleteChildren) then
    
    -- if deleting child categories simply delete them and close up the tree
    -- with the node width
    delete from category where lft between leftPos and rightPos
      and category_tree_id = catTreeId;
    update category set rgt = rgt - nodeWidth where rgt > rightPos
      and category_tree_id = catTreeId;
    update category set lft = lft - nodeWidth where lft > rightPos
      and category_tree_id = catTreeId;

  else

    -- if not deleting categories then reset the parent id for the categories
    -- that used to be linked to the one which we just deleted
    update category set parent_id = parentId where parent_id = categoryId
      and category_tree_id = catTreeId; 

    -- then update any child nodes below the node we just deleted with the 
    -- correct fullname and left and right positions 
    update        category 
    set           rgt = rgt - 1, 
                  lft = lft - 1, 
                  node_depth = node_depth - 1,
                  fullname = replace(replace(fullname, catName, ''), '//', '/')
    where         lft between leftPos and rightPos
    and category_tree_id = catTreeId;

    -- update the rest of the tree to close up the deleted category, -2
    update category set rgt = rgt - 2 where rgt > rightPos
      and category_tree_id = catTreeId;
    update category set lft = lft - 2 where lft > rightPos
      and category_tree_id = catTreeId;

  end if;

end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- move to child category procedure
-- -----------------------------------------------------------------------------
drop procedure if exists moveToChildOfCategory;
delimiter $$
create procedure moveToChildOfCategory(
  in categoryId int, 
  in categoryTreeId int,
  in moveToParentId int,
  in prepend boolean
)
proc: begin
  
  -- declare the variables
  declare parentFullName text default '';
  declare moveToFullName text default '';
  declare isMoveToSub boolean default false;
  declare nodeWidth int default 0;
  declare nodeDepthDelta int default 0;
  declare subtreeDelta int default 0;
  declare catLeft int default 0;
  declare catRight int default 0;
  declare catParentId int default 0;
  declare catNodeDepth int default 0;
  declare moveToLeft int default 0;
  declare moveToRight int default 0;
  declare moveToNodeDepth int default 0;
  
  -- we can't move to a category that doesn't exist and we can't move to self
  if (categoryId is null or categoryId <= 0 or moveToParentId is null
    or categoryId = moveToParentId) then
    leave proc;
  end if;
  
  -- get the variables for the category to move
  select        lft, rgt, parent_id, node_depth
  into          catLeft, catRight, catParentId, catNodeDepth
  from          category
  where         category_id = categoryId;
  
  -- create the temporary table for storing the subtree we are about to move
  -- we delete the table if it already exists, which it shouldn't
  drop temporary table if exists tempmovecats;
  create temporary table tempmovecats (
    category_id bigint unsigned not null auto_increment,
    category_tree_id varchar(50) not null,
    parent_id bigint unsigned not null,
    name varchar(100) not null,
    fullname text not null,
    description text,
    lft int unsigned not null,
    rgt int unsigned not null,
    node_depth int unsigned not null,
    is_alias boolean not null default false,
    alias_id bigint unsigned,
    constraint primary key (category_id),
    constraint uc01_tempmovecats unique (parent_id, name),   
    index idx01_tempmovecats (category_tree_id),
    index idx02_tempmovecats (parent_id),
    index idx03_tempmovecats (name), 
    index idx04_tempmovecats (lft),
    index idx05_tempmovecats (rgt),    
    index idx06_tempmovecats (node_depth)
  );
  
  -- copy the subtree over into the temporary table
  insert into tempmovecats
    select * from category where lft >= catLeft and rgt <= catRight
      and category_tree_id = categoryTreeId;
  
  -- we can't move into a subnode of the tree we are trying to move
  select        (count(*) = 1)
  into          isMoveToSub
  from          tempmovecats
  where         category_id = moveToParentId;
  if (isMoveToSub) then
    leave proc;
  end if;
  
  -- remove the subtree from the main category tree, which will automatically
  -- close up the tree, then get the node width
  call removeCategory(categoryId, true);
  set nodeWidth = (catRight - catLeft) + 1;
  
  -- are we moving to somewhere other than the root node or not
  if (moveToParentId > 0) then
    
    -- other than the root node, get the variables for the parent category we
    -- are moving into
    select            lft, rgt, fullname, node_depth
    into              moveToLeft, moveToRight, moveToFullName, moveToNodeDepth
    from              category
    where             category_id = moveToParentId;

  elseif (not prepend) then

    -- if root and we are appending, we only need to get the max right and add 1
    select          ifnull(max(rgt), 0) + 1
    into            moveToRight
    from            category;

  end if;
  
  -- get the delta for the node depth
  set nodeDepthDelta = ((moveToNodeDepth + 1) - catNodeDepth);

  -- widen the category tree as necessary for re-inserting the subtree, at the 
  -- same time get the delta for the subtree positions
  if (prepend) then
    set subtreeDelta = (moveToLeft - catLeft) + 1;
    update category set lft = lft + nodeWidth where lft > moveToLeft
      and category_tree_id = categoryTreeId;      
    update category set rgt = rgt + nodeWidth where rgt > moveToLeft
      and category_tree_id = categoryTreeId;
  else
    set subtreeDelta = (moveToRight - catLeft);
    update category set lft = lft + nodeWidth where lft > moveToRight
      and category_tree_id = categoryTreeId;      
    update category set rgt = rgt + nodeWidth where rgt >= moveToRight
      and category_tree_id = categoryTreeId;
  end if;
  
  -- if there is a parent category for the category we are moving
  if (catParentId > 0) then
    
    -- get the full name of the parent category
    select        fullname
    into          parentFullName
    from          category
    where         category_id = catParentId;
    
    -- remove the parent category prefix from the categories in the subtree
    update        tempmovecats 
    set           fullname = substr(fullname, length(parentFullName) + 2);

  end if;
  
  -- update the categories in the subtree with the correct positions and the 
  -- correct fullname for where it is going to be inserted, also correct the 
  -- node depth
  update        tempmovecats 
  set           fullname = concat(moveToFullName, '/', fullname),
                lft = lft + subtreeDelta, 
                rgt = rgt + subtreeDelta,
                node_depth = node_depth + nodeDepthDelta;
  
  -- update the parent id or the origin category we are moving
  update        tempmovecats
  set           parent_id = moveToParentId
  where         category_id = categoryId;
  
  -- insert the subtree from the temporary table back into the main tree
  insert into category
    select * from tempmovecats;
  
  -- drop the temporary table
  drop temporary table if exists tempmovecats;
                
end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- move to sibling category procedure
-- -----------------------------------------------------------------------------
drop procedure if exists moveToSiblingOfCategory;
delimiter $$
create procedure moveToSiblingOfCategory(
  in categoryId int, 
  in categoryTreeId int,
  in moveToSiblingId int, 
  in prepend boolean
)
proc: begin

  -- declare the variables
  declare parentFullName text default '';
  declare sibParentFullName text default '';
  declare moveToFullName text default '';
  declare isMoveToSub boolean default false;
  declare nodeWidth int default 0;
  declare nodeDepthDelta int default 0;
  declare subtreeDelta int default 0;
  declare catLeft int default 0;
  declare catRight int default 0;
  declare catParentId int default 0;
  declare catNodeDepth int default 0;
  declare moveToLeft int default 0;
  declare moveToRight int default 0;
  declare moveToNodeDepth int default 1;
  declare moveToSibParentId int default 0;

  -- we can't move to a category that doesn't exist and we can't move to self
  if (categoryId is null or categoryId <= 0 or moveToSiblingId is null 
    or moveToSiblingId <= 0 or categoryId = moveToSiblingId) then
    leave proc;
  end if;

  -- get the variables for the category to move
  select        lft, rgt, parent_id, node_depth
  into          catLeft, catRight, catParentId, catNodeDepth
  from          category
  where         category_id = categoryId;

  -- create the temporary table for storing the subtree we are about to move
  -- we delete the table if it already exists, which it shouldn't
  drop temporary table if exists tempmovecats;
  create temporary table tempmovecats (
    category_id bigint unsigned not null auto_increment,
    category_tree_id varchar(50) not null,
    parent_id bigint unsigned not null,
    name varchar(100) not null,
    fullname text not null,
    description text,
    lft int unsigned not null,
    rgt int unsigned not null,
    node_depth int unsigned not null,
    is_alias boolean not null default false,
    alias_id bigint unsigned,
    constraint primary key (category_id),
    constraint uc01_tempmovecats unique (parent_id, name),   
    index idx01_tempmovecats (category_tree_id),
    index idx02_tempmovecats (parent_id),
    index idx03_tempmovecats (name), 
    index idx04_tempmovecats (lft),
    index idx05_tempmovecats (rgt),    
    index idx06_tempmovecats (node_depth)
  );

  -- copy the subtree over into the temporary table
  insert into tempmovecats
    select * from category where lft >= catLeft and rgt <= catRight
    and category_tree_id = categoryTreeId;

  -- we can't move into a subnode of the tree we are trying to move
  select        (count(*) = 1)
  into          isMoveToSub
  from          tempmovecats
  where         category_id = moveToSiblingId;
  if (isMoveToSub) then
    leave proc;
  end if;

  -- remove the subtree from the main category tree, which will automatically
  -- close up the tree, then get the node width
  call removeCategory(categoryId, true);
  set nodeWidth = (catRight - catLeft) + 1;

  -- get the variables for the sibling category we are moving near
  select            lft, rgt, fullname, node_depth, parent_id
  into              moveToLeft, moveToRight, moveToFullName, moveToNodeDepth,
                    moveToSibParentId
  from              category
  where             category_id = moveToSiblingId;

  -- get the delta for the node depth
  set nodeDepthDelta = (moveToNodeDepth - catNodeDepth);

  -- widen the category tree as necessary for re-inserting the subtree, at the 
  -- same time get the delta for the subtree positions
  if (prepend) then
    set subtreeDelta = (moveToLeft - catLeft);
    update category set lft = lft + nodeWidth where lft >= moveToLeft
      and category_tree_id = categoryTreeId;      
    update category set rgt = rgt + nodeWidth where rgt >= moveToLeft
      and category_tree_id = categoryTreeId;
  else
    set subtreeDelta = (moveToRight - catLeft) + 1;
    update category set lft = lft + nodeWidth where lft > moveToRight
      and category_tree_id = categoryTreeId;      
    update category set rgt = rgt + nodeWidth where rgt > moveToRight
      and category_tree_id = categoryTreeId;
  end if;

  -- if there is a parent category for the category we are moving
  if (catParentId > 0) then

    -- get the full name of the parent category
    select        fullname
    into          parentFullName
    from          category
    where         category_id = catParentId;

    -- remove the parent category prefix from the categories in the subtree
    update        tempmovecats 
    set           fullname = substr(fullname, length(parentFullName) + 2);

  end if; 
  
  -- if the sibling has a parent category get its full name
  if (moveToSibParentId > 0) then
    select        fullname
    into          sibParentFullName
    from          category
    where         category_id = moveToSibParentId;
  end if; 

  -- update the categories in the subtree with the correct positions and the 
  -- correct fullname for where it is going to be inserted, also correct the 
  -- node depth
  update        tempmovecats 
  set           fullname = concat(sibParentFullName, fullname),
                lft = lft + subtreeDelta, 
                rgt = rgt + subtreeDelta,
                node_depth = node_depth + nodeDepthDelta;

  -- update the parent id or the origin category we are moving
  update        tempmovecats
  set           parent_id = moveToSibParentId
  where         category_id = categoryId;

  -- insert the subtree from the temporary table back into the main tree
  insert into category
    select * from tempmovecats;

  -- drop the temporary table
  drop temporary table if exists tempmovecats;
                
end $$
delimiter ;

-- -----------------------------------------------------------------------------
-- update category procedure
-- -----------------------------------------------------------------------------
drop procedure if exists updateCategory;
delimiter $$
create procedure updateCategory(
  in categoryId int,
  in categoryTreeId int,
  in newCatName varchar(50), 
  in newCatDesc varchar(100),
  in newAlias boolean,
  in newAliasId int
)
proc: begin
  
  declare leftPos int default 0;
  declare rightPos int default 0;
  declare nodeWidth int default 0;
  declare parentId int default 0;
  declare oldCatName varchar(50) default '';

  if (categoryId is null or categoryId <= 0) then
    leave proc;
  end if;
  
  -- get the variables for the category to update
  select      lft, rgt, (rgt - lft) + 1, parent_id, name
  into        leftPos, rightPos, nodeWidth, parentId, oldCatName
  from        category
  where       category_id = categoryId;
  
  -- update the category in the tree
  update      category
  set         name = newCatName,
              fullname = case
                when node_depth <= 1 then newCatName
                else concat(substring_index(
                  fullname, '/', node_depth), '/', newCatName)
              end,
              description = newCatDesc,
              is_alias = newAlias,
              alias_id = newAliasId
  where       category_id = categoryId;

  -- update the sub category full names
  update      category
  set         fullname = getFullCategoryName(parent_id, name)
  where       lft between leftPos and rightPos
  and         category_tree_id = categoryTreeId;

end $$
delimiter ;
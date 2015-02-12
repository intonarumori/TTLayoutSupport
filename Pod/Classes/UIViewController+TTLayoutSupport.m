//
//  UIViewController+TTLayoutSupport.m
//  TTLayoutSupport
//
//  Created by Steffen on 25.11.14.
//  Copyright (c) 2014 Steffen Neubauer. All rights reserved.
//

#import "UIViewController+TTLayoutSupport.h"
#import "TTLayoutSupportConstraint.h"
#import <objc/runtime.h>

@interface UIViewController (TTLayoutSupportPrivate)

// recorded apple's `UILayoutSupportConstraint` objects for topLayoutGuide
@property (nonatomic, strong) NSArray *tt_recordedTopLayoutSupportConstraints;

// recorded apple's `UILayoutSupportConstraint` objects for bottomLayoutGuide
@property (nonatomic, strong) NSArray *tt_recordedBottomLayoutSupportConstraints;

// custom layout constraint that has been added to control the topLayoutGuide
@property (nonatomic, strong) TTLayoutSupportConstraint *tt_topConstraint;

// custom layout constraint that has been added to control the bottomLayoutGuide
@property (nonatomic, strong) TTLayoutSupportConstraint *tt_bottomConstraint;

@end

#pragma mark - TTLayoutSupport

@implementation UIViewController (TTLayoutSupport)

+ (void)load
{
    [self swizzle:[self class] from:@selector(topLayoutGuide) to:@selector(tt_topLayoutGuide)];
    [self swizzle:[self class] from:@selector(bottomLayoutGuide) to:@selector(tt_bottomLayoutGuide)];
    [self swizzle:[self class] from:@selector(view) to:@selector(tt_view)];
}

+ (void)swizzle:(Class)class from:(SEL)originalSel to:(SEL)newSel
{
    Method originalMethod = class_getInstanceMethod(class, originalSel);
    Method newMethod = class_getInstanceMethod(class, newSel);
    
    if (class_addMethod(class, originalSel, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(class, newSel, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, newMethod);
    }
}

- (CGFloat)tt_topLayoutGuideLength
{
    return self.tt_topConstraint ? self.tt_topConstraint.constant : self.topLayoutGuide.length;
}

- (void)setTt_topLayoutGuideLength:(CGFloat)length
{
    [self tt_ensureCustomTopConstraint];
    
    self.tt_topConstraint.constant = length;
    
    [self tt_updateInsets:YES];
}

- (CGFloat)tt_bottomLayoutGuideLength
{
    return self.tt_bottomConstraint ? self.tt_bottomConstraint.constant : self.bottomLayoutGuide.length;
}

- (void)setTt_bottomLayoutGuideLength:(CGFloat)length
{
    [self tt_ensureCustomBottomConstraint];

    self.tt_bottomConstraint.constant = length;
    
    [self tt_updateInsets:NO];
}

- (void)tt_ensureCustomTopConstraint
{
    if (self.tt_topConstraint) {
        // already created
        return;
    }

    // recording does not work if view has never been accessed
    __unused UIView *view = self.view;
    
    // if topLayoutGuide has never been accessed, we did not record yet.
    __unused id<UILayoutSupport> topLayoutGuide = self.topLayoutGuide;

    NSAssert(self.tt_recordedTopLayoutSupportConstraints.count, @"Failed to record topLayoutGuide constraints. Is the controller's view added to the view hierarchy?");
    
    [self.view removeConstraints:self.tt_recordedTopLayoutSupportConstraints];
    
    NSArray *constraints =
        [TTLayoutSupportConstraint layoutSupportConstraintsWithView:self.view
                                                     topLayoutGuide:self.topLayoutGuide];

    // todo: less hacky?
    self.tt_topConstraint = [constraints firstObject];
    
    [self.view addConstraints:constraints];
}

- (void)tt_ensureCustomBottomConstraint
{
    if (self.tt_bottomConstraint) {
        // already created
        return;
    }

    // recording does not work if view has never been accessed
    __unused UIView *view = self.view;
    
    // if bottomLayoutGuide has never been accessed, we did not record yet.
    __unused id<UILayoutSupport> bottomLayoutGuide = self.bottomLayoutGuide;

    NSAssert(self.tt_recordedBottomLayoutSupportConstraints.count, @"Failed to record bottomLayoutGuide constraints. Is the controller's view added to the view hierarchy?");
    
    [self.view removeConstraints:self.tt_recordedBottomLayoutSupportConstraints];
    
    NSArray *constraints =
    [TTLayoutSupportConstraint layoutSupportConstraintsWithView:self.view
                                              bottomLayoutGuide:self.bottomLayoutGuide];
    
    // todo: less hacky?
    self.tt_bottomConstraint = [constraints firstObject];
    
    [self.view addConstraints:constraints];
}

- (void)tt_updateInsets:(BOOL)adjustsScrollPosition
{
    // don't update scroll view insets if developer didn't want it
    if (!self.automaticallyAdjustsScrollViewInsets) {
        return;
    }

    UIScrollView *scrollView;

    if ([self respondsToSelector:@selector(tableView)]) {
        scrollView = ((UITableViewController *)self).tableView;
    } else if ([self respondsToSelector:@selector(collectionView)]) {
        scrollView = ((UICollectionViewController *)self).collectionView;
    } else {
        scrollView = (UIScrollView *)self.view;
    }

    if ([scrollView isKindOfClass:[UIScrollView class]]) {
        CGPoint previousContentOffset = CGPointMake(scrollView.contentOffset.x, scrollView.contentOffset.y + scrollView.contentInset.top);

        UIEdgeInsets insets = UIEdgeInsetsMake(self.tt_topLayoutGuideLength, 0, self.tt_bottomLayoutGuideLength, 0);
        scrollView.contentInset = insets;
        scrollView.scrollIndicatorInsets = insets;
        
        if (adjustsScrollPosition && previousContentOffset.y == 0) {
            scrollView.contentOffset = CGPointMake(previousContentOffset.x, -scrollView.contentInset.top);
        }
    }
}

- (id<UILayoutSupport>)tt_topLayoutGuide
{
    if (self.tt_recordedTopLayoutSupportConstraints) {
        return [self tt_topLayoutGuide];
    }

    __block id<UILayoutSupport> topLayoutGuide;

    // record top layout guide support constraints,
    // so we can remove them later and replace with our own
    self.tt_recordedTopLayoutSupportConstraints = [self recordAddedConstraints:^{
        topLayoutGuide = [self tt_topLayoutGuide];
    }];

    return topLayoutGuide;
}

- (id<UILayoutSupport>)tt_bottomLayoutGuide
{
    if (self.tt_recordedBottomLayoutSupportConstraints) {
        // call super
        return [self tt_bottomLayoutGuide];
    }

    __block id<UILayoutSupport> bottomLayoutGuide;

    // record bottom layout guide support constraints,
    // so we can remove them later and replace with our own
    self.tt_recordedBottomLayoutSupportConstraints = [self recordAddedConstraints:^{
        // call super
        bottomLayoutGuide = [self tt_bottomLayoutGuide];
    }];

    return bottomLayoutGuide;
}

- (NSArray *)recordAddedConstraints:(dispatch_block_t)blockThatAddsConstraints
{
    // remember which constraints were there before creating bottomLayoutGuide
    NSSet *constraintsBefore = [NSSet setWithArray:self.view.constraints];

    // call block that adds constraints
    blockThatAddsConstraints();

    // remove constraints that were already there
    NSMutableSet *layoutSupportConstraints = [NSMutableSet setWithArray:self.view.constraints];
    [layoutSupportConstraints minusSet:constraintsBefore];

    // return recorded constraints
    return [layoutSupportConstraints allObjects];
}

#pragma mark -

- (UIView *)tt_view
{
    if(self.isViewLoaded)
    {
        return [self tt_view];
    }
    
    // create the view
    UIView *view = [self tt_view];
    
    // look for the support layout constraints that we set up internally for layout guides
    
    NSArray *constraints = view.constraints;
    
    NSMutableArray *recordedTopLayoutConstraints = [NSMutableArray array];
    NSMutableArray *recordedBottomLayoutConstraints = [NSMutableArray array];
    
    NSArray *supportConstraints = [self filterSupportConstraints:constraints];
    for(NSLayoutConstraint *constraint in supportConstraints)
    {
        if(constraint.firstItem == self.topLayoutGuide)
        {
            [recordedTopLayoutConstraints addObject:constraint];
        }
        else if(constraint.firstItem == self.bottomLayoutGuide)
        {
            [recordedBottomLayoutConstraints addObject:constraint];
        }
    }
    
    // store them
    self.tt_recordedBottomLayoutSupportConstraints = recordedBottomLayoutConstraints;
    self.tt_recordedTopLayoutSupportConstraints = recordedTopLayoutConstraints;
    
    // they will be exchanged if the toplayoutguidelength is accessed or modified
    
    return view;
}

- (NSArray *)filterSupportConstraints:(NSArray *)constraints
{
    NSMutableArray *supportConstraints = [NSMutableArray array];
    
    for(NSLayoutConstraint *constraint in constraints)
    {
        if(![constraint isMemberOfClass:[NSLayoutConstraint class]])
        {
            BOOL isLayoutGuide = [constraint.firstItem conformsToProtocol:@protocol(UILayoutSupport)];
            
            if(isLayoutGuide)
            {
                //id<UILayoutSupport> guide = (id<UILayoutSupport>)constraint.firstItem;
                [supportConstraints addObject:constraint];
            }
        }
    }
    return supportConstraints;
}

@end

#pragma mark - TTLayoutSupportPrivate

@implementation UIViewController (TTLayoutSupportPrivate)

- (NSLayoutConstraint *)tt_topConstraint
{
    return objc_getAssociatedObject(self, @selector(tt_topConstraint));
}

- (void)setTt_topConstraint:(NSLayoutConstraint *)constraint
{
    objc_setAssociatedObject(self, @selector(tt_topConstraint), constraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSLayoutConstraint *)tt_bottomConstraint
{
    return objc_getAssociatedObject(self, @selector(tt_bottomConstraint));
}

- (void)setTt_bottomConstraint:(NSLayoutConstraint *)constraint
{
    objc_setAssociatedObject(self, @selector(tt_bottomConstraint), constraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSArray *)tt_recordedTopLayoutSupportConstraints
{
    return objc_getAssociatedObject(self, @selector(tt_recordedTopLayoutSupportConstraints));
}

- (void)setTt_recordedTopLayoutSupportConstraints:(NSArray *)constraints
{
    objc_setAssociatedObject(self, @selector(tt_recordedTopLayoutSupportConstraints), constraints, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSArray *)tt_recordedBottomLayoutSupportConstraints
{
    return objc_getAssociatedObject(self, @selector(tt_recordedBottomLayoutSupportConstraints));
}

- (void)setTt_recordedBottomLayoutSupportConstraints:(NSArray *)constraints
{
    objc_setAssociatedObject(self, @selector(tt_recordedBottomLayoutSupportConstraints), constraints, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

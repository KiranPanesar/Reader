//
//	ReaderViewController.m
//	Reader v2.7.2
//
//	Created by Julius Oklamcak on 2011-07-01.
//	Copyright © 2011-2013 Julius Oklamcak. All rights reserved.
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights to
//	use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
//	of the Software, and to permit persons to whom the Software is furnished to
//	do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in all
//	copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//	OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//	CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "ReaderConstants.h"
#import "ReaderViewController.h"
#import "ThumbsViewController.h"
#import "ReaderMainPagebar.h"
#import "ReaderContentView.h"
#import "ReaderThumbCache.h"
#import "ReaderThumbQueue.h"
#import "ReaderLanguage.h"

#import "UINavigationController+NavBarAnimation.h"

#import <MessageUI/MessageUI.h>

static NSString *ReaderActionSheetItemTitleEmail    = nil;
static NSString *ReaderActionSheetItemTitlePrint    = nil;
static NSString *ReaderActionSheetItemTitleOpenIn   = nil;
static NSString *ReaderActionSheetItemTitleBookmark = nil;
static NSString *ReaderActionSheetItemTitleUnbookmark = nil;

@interface ReaderViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate, UIActionSheetDelegate, MFMailComposeViewControllerDelegate,
									ReaderMainPagebarDelegate, ReaderContentViewDelegate, ThumbsViewControllerDelegate>
@end

@implementation ReaderViewController
{
	UIScrollView *theScrollView;

    UIBarButtonItem *doneBarButtonItem;
    UIBarButtonItem *thumbsBarButton;
    UIBarButtonItem *moreBarButtonItem;
    
	ReaderMainPagebar *mainPagebar;

	NSMutableDictionary *contentViews;

    UIActionSheet *moreActionSheet;
	UIPrintInteractionController *printInteraction;
    UIDocumentInteractionController *interactionController;
    
    NSInteger currentScrollViewPage;
    
	CGSize lastAppearSize;

	NSDate *lastHideTime;

	BOOL isVisible;
}

#pragma mark Constants

#define PAGING_VIEWS 3

#define STATUS_HEIGHT 20.0f

#define TOOLBAR_HEIGHT 44.0f
#define PAGEBAR_HEIGHT 48.0f

#define TAP_AREA_SIZE 48.0f

#pragma mark Properties

@synthesize delegate;

#pragma mark Support methods

+ (void)initialize
{
    if (ReaderActionSheetItemTitleEmail == nil) {
        ReaderActionSheetItemTitleEmail    = [ReaderLanguage get:@"Email"];
    }
    if (ReaderActionSheetItemTitlePrint == nil) {
        ReaderActionSheetItemTitlePrint    = [ReaderLanguage get:@"Print"];
    }
    if (ReaderActionSheetItemTitleOpenIn == nil) {
        ReaderActionSheetItemTitleOpenIn   = [ReaderLanguage get:@"Open In..."];
    }
    if (ReaderActionSheetItemTitleBookmark == nil) {
        ReaderActionSheetItemTitleBookmark = [ReaderLanguage get:@"Bookmark"];
    }
    if (ReaderActionSheetItemTitleUnbookmark == nil) {
        ReaderActionSheetItemTitleUnbookmark = [ReaderLanguage get:@"Unbookmark"];
    }
}

- (void)updateScrollViewContentSize
{
	NSInteger count = [_document.pageCount integerValue];

	if (count > PAGING_VIEWS) count = PAGING_VIEWS; // Limit

	CGFloat contentHeight = theScrollView.bounds.size.height;
    
	CGFloat contentWidth = (theScrollView.bounds.size.width * count);

	theScrollView.contentSize = CGSizeMake(contentWidth, contentHeight);
}

- (void)updateScrollViewContentViews
{
	[self updateScrollViewContentSize]; // Update the content size

	NSMutableIndexSet *pageSet = [NSMutableIndexSet indexSet]; // Page set

	[contentViews enumerateKeysAndObjectsUsingBlock: // Enumerate content views
		^(id key, id object, BOOL *stop)
		{
			ReaderContentView *contentView = object; [pageSet addIndex:contentView.tag];
		}
	];

	__block CGRect viewRect = CGRectZero; viewRect.size = theScrollView.bounds.size;

	__block CGPoint contentOffset = CGPointZero; NSInteger page = [_document.pageNumber integerValue];

	[pageSet enumerateIndexesUsingBlock: // Enumerate page number set
		^(NSUInteger number, BOOL *stop)
		{
			NSNumber *key = [NSNumber numberWithInteger:number]; // # key

			ReaderContentView *contentView = [contentViews objectForKey:key];

			contentView.frame = viewRect; if (page == number) contentOffset = viewRect.origin;

			viewRect.origin.x += viewRect.size.width; // Next view frame position
		}
	];

	if (CGPointEqualToPoint(theScrollView.contentOffset, contentOffset) == false)
	{
		theScrollView.contentOffset = contentOffset; // Update content offset
	}
}

- (void)showDocumentPage:(NSInteger)page
{
	if (page != _currentPage) // Only if different
	{
		NSInteger minValue; NSInteger maxValue;
		NSInteger maxPage = [_document.pageCount integerValue];
		NSInteger minPage = 1;

		if ((page < minPage) || (page > maxPage)) return;

		if (maxPage <= PAGING_VIEWS) // Few pages
		{
			minValue = minPage;
			maxValue = maxPage;
		}
		else // Handle more pages
		{
			minValue = (page - 1);
			maxValue = (page + 1);

			if (minValue < minPage)
				{minValue++; maxValue++;}
			else
				if (maxValue > maxPage)
					{minValue--; maxValue--;}
		}

		NSMutableIndexSet *newPageSet = [NSMutableIndexSet new];

		NSMutableDictionary *unusedViews = [contentViews mutableCopy];

		CGRect viewRect = CGRectZero; viewRect.size = theScrollView.bounds.size;

		for (NSInteger number = minValue; number <= maxValue; number++)
		{
			NSNumber *key = [NSNumber numberWithInteger:number]; // # key

			ReaderContentView *contentView = [contentViews objectForKey:key];

			if (contentView == nil) // Create a brand new document content view
			{
				NSURL *fileURL = _document.fileURL; NSString *phrase = _document.password; // Document properties

				contentView = [[ReaderContentView alloc] initWithFrame:viewRect fileURL:fileURL page:number password:phrase];

				[theScrollView addSubview:contentView]; [contentViews setObject:contentView forKey:key];

				contentView.message = self; [newPageSet addIndex:number];
			}
			else // Reposition the existing content view
			{
				contentView.frame = viewRect; [contentView zoomReset];

				[unusedViews removeObjectForKey:key];
			}

			viewRect.origin.x += viewRect.size.width;
		}

		[unusedViews enumerateKeysAndObjectsUsingBlock: // Remove unused views
			^(id key, id object, BOOL *stop)
			{
				[contentViews removeObjectForKey:key];

				ReaderContentView *contentView = object;

				[contentView removeFromSuperview];
			}
		];

		unusedViews = nil; // Release unused views

		CGFloat viewWidthX1 = viewRect.size.width;
		CGFloat viewWidthX2 = (viewWidthX1 * 2.0f);

		CGPoint contentOffset = CGPointZero;

		if (maxPage >= PAGING_VIEWS)
		{
			if (page == maxPage)
				contentOffset.x = viewWidthX2;
			else
				if (page != minPage)
					contentOffset.x = viewWidthX1;
		}
		else
			if (page == (PAGING_VIEWS - 1))
				contentOffset.x = viewWidthX1;

		if (CGPointEqualToPoint(theScrollView.contentOffset, contentOffset) == false)
		{
			theScrollView.contentOffset = contentOffset; // Update content offset
		}

		if ([_document.pageNumber integerValue] != page) // Only if different
		{
			_document.pageNumber = [NSNumber numberWithInteger:page]; // Update page number
		}

		NSURL *fileURL = _document.fileURL; NSString *phrase = _document.password; NSString *guid = _document.guid;

		if ([newPageSet containsIndex:page] == YES) // Preview visible page first
		{
			NSNumber *key = [NSNumber numberWithInteger:page]; // # key

			ReaderContentView *targetView = [contentViews objectForKey:key];

			[targetView showPageThumb:fileURL page:page password:phrase guid:guid];

			[newPageSet removeIndex:page]; // Remove visible page from set
		}

		[newPageSet enumerateIndexesWithOptions:NSEnumerationReverse usingBlock: // Show previews
			^(NSUInteger number, BOOL *stop)
			{
				NSNumber *key = [NSNumber numberWithInteger:number]; // # key

				ReaderContentView *targetView = [contentViews objectForKey:key];

				[targetView showPageThumb:fileURL page:number password:phrase guid:guid];
			}
		];

		newPageSet = nil; // Release new page set

		[mainPagebar updatePagebar]; // Update the pagebar display

		_currentPage = page; // Track current page number
	}
}

- (void)showDocument:(id)object
{
	[self updateScrollViewContentSize]; // Set content size

	[self showDocumentPage:[_document.pageNumber integerValue]];

	_document.lastOpen = [NSDate date]; // Update last opened date

	isVisible = YES; // iOS present modal bodge
    
}

#pragma mark UIViewController methods

- (id)initWithReaderDocument:(ReaderDocument *)object
{
	id reader = nil; // ReaderViewController object

	if ((object != nil) && ([object isKindOfClass:[ReaderDocument class]]))
	{
		if ((self = [super initWithNibName:nil bundle:nil])) // Designated initializer
		{
			NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

			[notificationCenter addObserver:self selector:@selector(applicationWill:) name:UIApplicationWillTerminateNotification object:nil];

			[notificationCenter addObserver:self selector:@selector(applicationWill:) name:UIApplicationWillResignActiveNotification object:nil];

			[object updateProperties]; _document = object; // Retain the supplied ReaderDocument object for our use

			[ReaderThumbCache touchThumbCacheWithGUID:object.guid]; // Touch the document thumb cache directory

			reader = self; // Return an initialized ReaderViewController object
		}
	}

	return reader;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	assert(_document != nil); // Must have a valid ReaderDocument
    [self setAutomaticallyAdjustsScrollViewInsets:NO];
    
	self.view.backgroundColor = [UIColor colorWithRed:189/255.0f green:195/255.0f blue:199/255.0f alpha:1.0]; // Neutral gray

	theScrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds]; // UIScrollView
	theScrollView.autoresizesSubviews = NO;
    theScrollView.contentMode = UIViewContentModeRedraw;
	theScrollView.showsHorizontalScrollIndicator = NO;
    theScrollView.showsVerticalScrollIndicator = NO;
	theScrollView.scrollsToTop = NO;
    theScrollView.delaysContentTouches = NO;
    theScrollView.pagingEnabled = YES;
	theScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	theScrollView.backgroundColor = [UIColor clearColor];
    theScrollView.delegate = self;
	
    [self.view addSubview:theScrollView];
    
    [self setUpBarButtonItems];
    
	CGRect toolbarRect = self.view.bounds; // Toolbar frame
	toolbarRect.size.height = TOOLBAR_HEIGHT; // Default toolbar height
    
    [[self navigationController] setNavigationBarHidden:NO animated:NO];
    
	CGRect pagebarRect = self.view.bounds;; // Pagebar frame
	pagebarRect.origin.y = (pagebarRect.size.height - PAGEBAR_HEIGHT);
	pagebarRect.size.height = PAGEBAR_HEIGHT; // Default pagebar height

	mainPagebar = [[ReaderMainPagebar alloc] initWithFrame:pagebarRect document:_document]; // ReaderMainPagebar
	mainPagebar.pagebarDelegate = self; // ReaderMainPagebarDelegate
    [mainPagebar setBackgroundColor:[UIColor colorWithWhite:1.0f alpha:0.96f]];
    
	[self.view addSubview:mainPagebar];

	UITapGestureRecognizer *singleTapOne = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
	singleTapOne.numberOfTouchesRequired = 1; singleTapOne.numberOfTapsRequired = 1; singleTapOne.delegate = self;
	[self.view addGestureRecognizer:singleTapOne];

	UITapGestureRecognizer *doubleTapOne = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
	doubleTapOne.numberOfTouchesRequired = 1; doubleTapOne.numberOfTapsRequired = 2; doubleTapOne.delegate = self;
	[self.view addGestureRecognizer:doubleTapOne];

	UITapGestureRecognizer *doubleTapTwo = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
	doubleTapTwo.numberOfTouchesRequired = 2; doubleTapTwo.numberOfTapsRequired = 2; doubleTapTwo.delegate = self;
	[self.view addGestureRecognizer:doubleTapTwo];

	[singleTapOne requireGestureRecognizerToFail:doubleTapOne]; // Single tap requires double tap to fail

	contentViews = [NSMutableDictionary new]; lastHideTime = [NSDate date];
}

-(void)setUpBarButtonItems {
    if ([self isPresentedModally]) {
        doneBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:[ReaderLanguage get:@"Done"] style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(pushDoneBarButtonItem:)];
        [self.navigationItem setLeftBarButtonItem:doneBarButtonItem];
        
    }
    NSMutableArray *buttons = [[NSMutableArray alloc] init];
#if (READER_ENABLE_MORE_BUTTON == TRUE) // Option
    moreBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                      target:self
                                                                      action:@selector(pushActionBarButtonItem:)];
    
    [buttons addObject:moreBarButtonItem];
#endif
    
#if (READER_ENABLE_THUMBS == TRUE)
    thumbsBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Reader.bundle/Reader-Thumbs"]
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(pushThumbsBarButtonItem:)];
    [buttons addObject:thumbsBarButton];
#endif
    
    if ([buttons count]) {
        [self.navigationItem setRightBarButtonItems:buttons];
    }

}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	if (CGSizeEqualToSize(lastAppearSize, CGSizeZero) == false)
	{
		if (CGSizeEqualToSize(lastAppearSize, self.view.bounds.size) == false)
		{
			[self updateScrollViewContentViews]; // Update content views
		}

		lastAppearSize = CGSizeZero; // Reset view size tracking
	}
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	if (CGSizeEqualToSize(theScrollView.contentSize, CGSizeZero)) // First time
	{
		[self performSelector:@selector(showDocument:) withObject:nil afterDelay:0.02];
	}

#if (READER_DISABLE_IDLE == TRUE) // Option

	[UIApplication sharedApplication].idleTimerDisabled = YES;

#endif // end of READER_DISABLE_IDLE Option
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
    [moreActionSheet dismissWithClickedButtonIndex:-1 animated:NO];
    [printInteraction dismissAnimated:NO];
    [interactionController dismissMenuAnimated:NO];
    [interactionController dismissPreviewAnimated:NO];
    
	lastAppearSize = self.view.bounds.size; // Track view size

#if (READER_DISABLE_IDLE == TRUE) // Option

	[UIApplication sharedApplication].idleTimerDisabled = NO;

#endif // end of READER_DISABLE_IDLE Option
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (void)viewDidUnload
{
#ifdef DEBUG
	NSLog(@"%s", __FUNCTION__);
#endif

	mainPagebar = nil;

	theScrollView = nil; contentViews = nil; lastHideTime = nil;

	lastAppearSize = CGSizeZero; _currentPage = 0; currentScrollViewPage = 0;

	[super viewDidUnload];
}

- (BOOL)prefersStatusBarHidden
{
	return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
	return UIStatusBarStyleLightContent;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	if (isVisible == NO) return; // iOS present modal bodge

	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
	{
		if (printInteraction != nil) [printInteraction dismissAnimated:NO];
	}
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
	if (isVisible == NO) return; // iOS present modal bodge

	[self updateScrollViewContentViews]; // Update content views

	lastAppearSize = CGSizeZero; // Reset view size tracking
}

/*
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
	//if (isVisible == NO) return; // iOS present modal bodge

	//if (fromInterfaceOrientation == self.interfaceOrientation) return;
}
*/

- (void)didReceiveMemoryWarning
{
#ifdef DEBUG
	NSLog(@"%s", __FUNCTION__);
#endif

	[super didReceiveMemoryWarning];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark UIScrollViewDelegate methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    NSInteger scrollViewPage = 0;
    CGFloat pageWidth = scrollView.frame.size.width;
    CGFloat contentOffsetX = scrollView.contentOffset.x;
    
    if ((currentScrollViewPage == 0 && contentOffsetX < pageWidth) || contentOffsetX <= 0) {
        scrollViewPage = 0;
    } else if ((currentScrollViewPage == 2 && contentOffsetX <= pageWidth) || (currentScrollViewPage != 2 && contentOffsetX < 2 * pageWidth)) {
        scrollViewPage = 1;
    } else {
        scrollViewPage = 2;
    }
    
    if (scrollViewPage != currentScrollViewPage) {
        currentScrollViewPage = scrollViewPage;
        
        CGFloat contentOffsetX = scrollView.frame.size.width * scrollViewPage;
        
        __block NSInteger page = 0;
        
        [contentViews enumerateKeysAndObjectsUsingBlock:^(id key, ReaderContentView *contentView, BOOL *stop) {
            if (contentView.frame.origin.x == contentOffsetX) {
                page = contentView.tag; *stop = YES;
            }
        }];
        
        if (page != 0)  {
            [self showDocumentPage:page]; // Show the page
        }
    }
}

//- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
//{
//	__block NSInteger page = 0;
//
//	CGFloat contentOffsetX = scrollView.contentOffset.x;
//
//	[contentViews enumerateKeysAndObjectsUsingBlock: // Enumerate content views
//		^(id key, id object, BOOL *stop)
//		{
//			ReaderContentView *contentView = object;
//
//			if (contentView.frame.origin.x == contentOffsetX)
//			{
//				page = contentView.tag; *stop = YES;
//			}
//		}
//	];
//
//	if (page != 0) [self showDocumentPage:page]; // Show the page
//}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
	[self showDocumentPage:theScrollView.tag]; // Show page

	theScrollView.tag = 0; // Clear page number tag
}

#pragma mark UIGestureRecognizerDelegate methods

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
	if ([touch.view isKindOfClass:[UIScrollView class]]) return YES;

	return NO;
}

#pragma mark UIGestureRecognizer action methods

- (void)decrementPageNumber
{
	if (theScrollView.tag == 0) // Scroll view did end
	{
		NSInteger page = [_document.pageNumber integerValue];
		NSInteger maxPage = [_document.pageCount integerValue];
		NSInteger minPage = 1; // Minimum

		if ((maxPage > minPage) && (page != minPage))
		{
			CGPoint contentOffset = theScrollView.contentOffset;

			contentOffset.x -= theScrollView.bounds.size.width; // -= 1

			[theScrollView setContentOffset:contentOffset animated:YES];

			theScrollView.tag = (page - 1); // Decrement page number
		}
	}
}

- (void)incrementPageNumber
{
	if (theScrollView.tag == 0) // Scroll view did end
	{
		NSInteger page = [_document.pageNumber integerValue];
		NSInteger maxPage = [_document.pageCount integerValue];
		NSInteger minPage = 1; // Minimum

		if ((maxPage > minPage) && (page != maxPage))
		{
			CGPoint contentOffset = theScrollView.contentOffset;

			contentOffset.x += theScrollView.bounds.size.width; // += 1

			[theScrollView setContentOffset:contentOffset animated:YES];

			theScrollView.tag = (page + 1); // Increment page number
		}
	}
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer
{
	if (recognizer.state == UIGestureRecognizerStateRecognized)
	{
		CGRect viewRect = recognizer.view.bounds; // View bounds

		CGPoint point = [recognizer locationInView:recognizer.view];

		CGRect areaRect = CGRectInset(viewRect, TAP_AREA_SIZE, 0.0f); // Area

		if (CGRectContainsPoint(areaRect, point)) // Single tap is inside the area
		{
			NSInteger page = [_document.pageNumber integerValue]; // Current page #

			NSNumber *key = [NSNumber numberWithInteger:page]; // Page number key

			ReaderContentView *targetView = [contentViews objectForKey:key];

			id target = [targetView processSingleTap:recognizer]; // Target

			if (target != nil) // Handle the returned target object
			{
				if ([target isKindOfClass:[NSURL class]]) // Open a URL
				{
					NSURL *url = (NSURL *)target; // Cast to a NSURL object

					if (url.scheme == nil) // Handle a missing URL scheme
					{
						NSString *www = url.absoluteString; // Get URL string

						if ([www hasPrefix:@"www"] == YES) // Check for 'www' prefix
						{
							NSString *http = [NSString stringWithFormat:@"http://%@", www];

							url = [NSURL URLWithString:http]; // Proper http-based URL
						}
					}

					if ([[UIApplication sharedApplication] openURL:url] == NO)
					{
						#ifdef DEBUG
							NSLog(@"%s '%@'", __FUNCTION__, url); // Bad or unknown URL
						#endif
					}
				}
				else // Not a URL, so check for other possible object type
				{
					if ([target isKindOfClass:[NSNumber class]]) // Goto page
					{
						NSInteger value = [target integerValue]; // Number

						[self showDocumentPage:value]; // Show the page
					}
				}
			}
			else // Nothing active tapped in the target content view
			{
				if ([lastHideTime timeIntervalSinceNow] < -0.75) // Delay since hide
				{
					if (([self.navigationController isNavigationBarHidden] == YES) || (mainPagebar.hidden == YES))
					{
						[self.navigationController setNavigationBarHidden:NO animation:ReaderNavigationBarAnimationFade];
                        [mainPagebar showPagebar]; // Show
					}
				}
			}

			return;
		}

		CGRect nextPageRect = viewRect;
		nextPageRect.size.width = TAP_AREA_SIZE;
		nextPageRect.origin.x = (viewRect.size.width - TAP_AREA_SIZE);

		if (CGRectContainsPoint(nextPageRect, point)) // page++ area
		{
			[self incrementPageNumber]; return;
		}

		CGRect prevPageRect = viewRect;
		prevPageRect.size.width = TAP_AREA_SIZE;

		if (CGRectContainsPoint(prevPageRect, point)) // page-- area
		{
			[self decrementPageNumber]; return;
		}
	}
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer
{
	if (recognizer.state == UIGestureRecognizerStateRecognized)
	{
		CGRect viewRect = recognizer.view.bounds; // View bounds

		CGPoint point = [recognizer locationInView:recognizer.view];

		CGRect zoomArea = CGRectInset(viewRect, TAP_AREA_SIZE, TAP_AREA_SIZE);

		if (CGRectContainsPoint(zoomArea, point)) // Double tap is in the zoom area
		{
			NSInteger page = [_document.pageNumber integerValue]; // Current page #

			NSNumber *key = [NSNumber numberWithInteger:page]; // Page number key

			ReaderContentView *targetView = [contentViews objectForKey:key];

			switch (recognizer.numberOfTouchesRequired) // Touches count
			{
				case 1: // One finger double tap: zoom ++
				{
					[targetView zoomIncrement]; break;
				}

				case 2: // Two finger double tap: zoom --
				{
					[targetView zoomDecrement]; break;
				}
			}

			return;
		}

		CGRect nextPageRect = viewRect;
		nextPageRect.size.width = TAP_AREA_SIZE;
		nextPageRect.origin.x = (viewRect.size.width - TAP_AREA_SIZE);

		if (CGRectContainsPoint(nextPageRect, point)) // page++ area
		{
			[self incrementPageNumber]; return;
		}

		CGRect prevPageRect = viewRect;
		prevPageRect.size.width = TAP_AREA_SIZE;

		if (CGRectContainsPoint(prevPageRect, point)) // page-- area
		{
			[self decrementPageNumber]; return;
		}
	}
}

-(BOOL)isPresentedModally {
    return self.presentingViewController.presentedViewController == self
    || self.navigationController.presentingViewController.presentedViewController == self.navigationController
    || [self.tabBarController.presentingViewController isKindOfClass:[UITabBarController class]];
}

#pragma mark ReaderContentViewDelegate methods

- (void)contentView:(ReaderContentView *)contentView touchesBegan:(NSSet *)touches
{
	if (([self.navigationController isNavigationBarHidden] == NO) || (mainPagebar.hidden == NO))
	{
		if (touches.count == 1) // Single touches only
		{
			UITouch *touch = [touches anyObject]; // Touch info

			CGPoint point = [touch locationInView:self.view]; // Touch location

			CGRect areaRect = CGRectInset(self.view.bounds, TAP_AREA_SIZE, TAP_AREA_SIZE);

			if (CGRectContainsPoint(areaRect, point) == false) return;
		}

		[self.navigationController setNavigationBarHidden:YES animation:ReaderNavigationBarAnimationFade];
        [mainPagebar hidePagebar]; // Hide

		lastHideTime = [NSDate date];
    }
}

#pragma mark Toolbar button actions

-(void)pushDoneBarButtonItem:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)pushActionBarButtonItem:(id)sender {
    
    moreActionSheet = [[UIActionSheet alloc] initWithTitle:[ReaderLanguage get:@"More"]
                                                  delegate:self
                                         cancelButtonTitle:nil
                                    destructiveButtonTitle:nil
                                         otherButtonTitles:nil];
#if (READER_BOOKMARKS == TRUE) //option
    NSInteger page = [_document.pageNumber integerValue];
    BOOL bookmarked = [_document.bookmarks containsIndex:page];
    [moreActionSheet addButtonWithTitle:(bookmarked ? ReaderActionSheetItemTitleUnbookmark : ReaderActionSheetItemTitleBookmark)];
#endif
#if (READER_ENABLE_MAIL == TRUE) //option
    [moreActionSheet addButtonWithTitle:ReaderActionSheetItemTitleEmail];
#endif
    [moreActionSheet addButtonWithTitle:ReaderActionSheetItemTitleOpenIn];
#if (READER_ENABLE_PRINT == TRUE) //option
    [moreActionSheet addButtonWithTitle:ReaderActionSheetItemTitlePrint];
#endif
    [moreActionSheet addButtonWithTitle:[ReaderLanguage get:@"Dismiss"]];
    moreActionSheet.cancelButtonIndex = moreActionSheet.numberOfButtons - 1;
    [moreActionSheet showFromBarButtonItem:moreBarButtonItem animated:YES];
}

-(void)pushThumbsBarButtonItem:(id)sender {
    
	ThumbsViewController *thumbsViewController = [[ThumbsViewController alloc] initWithReaderDocument:_document];
    
	thumbsViewController.delegate = self; thumbsViewController.title = self.title;
    
	thumbsViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
	thumbsViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:thumbsViewController];
    
	[self presentViewController:navigationController animated:YES completion:NULL];
}

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *buttonTitle = [actionSheet buttonTitleAtIndex:buttonIndex];
    
    if ([buttonTitle isEqualToString:ReaderActionSheetItemTitleBookmark]) {
        [self actionSheetBookmarkDocument];
    } else if ([buttonTitle isEqualToString:ReaderActionSheetItemTitleUnbookmark]) {
        [self actionSheetUnbookmarkDocument];
    } else if ([buttonTitle isEqualToString:ReaderActionSheetItemTitleEmail]) {
        [self actionSheetEmailDocument];
    } else if ([buttonTitle isEqualToString:ReaderActionSheetItemTitleOpenIn]) {
        [self actionSheetOpenDocument];
    } else if ([buttonTitle isEqualToString:ReaderActionSheetItemTitlePrint]) {
        [self actionSheetPrintDocument];
    }
}

-(void)actionSheetBookmarkDocument {
    
    [_document.bookmarks addIndex:[_document.pageNumber integerValue]];
}

-(void)actionSheetUnbookmarkDocument {
    [_document.bookmarks removeIndex:[_document.pageNumber integerValue]];
}

-(void)actionSheetEmailDocument {
	if ([MFMailComposeViewController canSendMail] == NO) return;
    
	unsigned long long fileSize = [_document.fileSize unsignedLongLongValue];
    
	if (fileSize < (unsigned long long)15728640) // Check attachment size limit (15MB)
	{
		NSURL *fileURL = _document.fileURL; NSString *fileName = _document.fileName; // Document
        
		NSData *attachment = [NSData dataWithContentsOfURL:fileURL options:(NSDataReadingMapped|NSDataReadingUncached) error:nil];
        
		if (attachment != nil) // Ensure that we have valid document file attachment data
		{
			MFMailComposeViewController *mailComposer = [MFMailComposeViewController new];
            
			[mailComposer addAttachmentData:attachment mimeType:@"application/pdf" fileName:fileName];
            
			[mailComposer setSubject:fileName]; // Use the document file name for the subject
            
			mailComposer.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
			mailComposer.modalPresentationStyle = UIModalPresentationFormSheet;
            
			mailComposer.mailComposeDelegate = self; // Set the delegate
            
			[self presentViewController:mailComposer animated:YES completion:NULL];
		}
	}
}

-(void)actionSheetOpenDocument {
    interactionController = [UIDocumentInteractionController interactionControllerWithURL:[_document fileURL]];
    [interactionController presentOptionsMenuFromBarButtonItem:moreBarButtonItem animated:YES];
}

-(void)actionSheetPrintDocument {
    Class printInteractionController = NSClassFromString(@"UIPrintInteractionController");
    
	if ((printInteractionController != nil) && [printInteractionController isPrintingAvailable])
	{
		NSURL *fileURL = _document.fileURL; // Document file URL
        
		printInteraction = [printInteractionController sharedPrintController];
        
		if ([printInteractionController canPrintURL:fileURL] == YES) // Check first
		{
			UIPrintInfo *printInfo = [NSClassFromString(@"UIPrintInfo") printInfo];
            
			printInfo.duplex = UIPrintInfoDuplexLongEdge;
			printInfo.outputType = UIPrintInfoOutputGeneral;
			printInfo.jobName = _document.fileName;
            
			printInteraction.printInfo = printInfo;
			printInteraction.printingItem = fileURL;
			printInteraction.showsPageRange = YES;
            
            [printInteraction presentFromBarButtonItem:moreBarButtonItem animated:YES completionHandler:nil];
		}
    }
}

-(void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark ThumbsViewControllerDelegate methods

- (void)dismissThumbsViewController:(ThumbsViewController *)viewController
{
	[self dismissViewControllerAnimated:YES completion:NULL]; // Dismiss
}

- (void)thumbsViewController:(ThumbsViewController *)viewController gotoPage:(NSInteger)page
{
	[self showDocumentPage:page]; // Show the page
}

#pragma mark ReaderMainPagebarDelegate methods

- (void)pagebar:(ReaderMainPagebar *)pagebar gotoPage:(NSInteger)page
{
	[self showDocumentPage:page]; // Show the page
}

#pragma mark UIApplication notification methods

- (void)applicationWill:(NSNotification *)notification
{
	[_document saveReaderDocument]; // Save any ReaderDocument object changes

	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
	{
		if (printInteraction != nil) [printInteraction dismissAnimated:NO];
	}
}

@end

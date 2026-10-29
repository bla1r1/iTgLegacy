#import <UIKit/UIKit.h>
#import "TGTextField.h"
#import "TGButton.h"

NS_ASSUME_NONNULL_BEGIN

@class TGSearchBar;

@protocol TGSearchBarDelegate <NSObject>
@optional
- (void)searchBar:(TGSearchBar *)searchBar textDidChange:(NSString *)searchText;
- (void)searchBarSearchButtonClicked:(TGSearchBar *)searchBar;
- (void)searchBarCancelButtonClicked:(TGSearchBar *)searchBar;
- (BOOL)searchBarShouldBeginEditing:(TGSearchBar *)searchBar;
- (void)searchBarTextDidBeginEditing:(TGSearchBar *)searchBar;
- (void)searchBarTextDidEndEditing:(TGSearchBar *)searchBar;
@end

/// Tactile iOS 6 skeuomorphic search bar component with satin textured background,
/// recessed search well, clear button, and animated sliding Cancel button.
@interface TGSearchBar : UIView <UITextFieldDelegate>

@property (nonatomic, weak, nullable) id<TGSearchBarDelegate> delegate;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, strong, readonly) TGTextField *textField;
@property (nonatomic, strong, readonly) TGButton *cancelButton;
@property (nonatomic, assign, getter=isEditing) BOOL editing;

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

module BucketSale.View exposing (root)

import BigInt exposing (BigInt)
import BucketSale.Types exposing (..)
import CmdUp exposing (CmdUp)
import CommonTypes exposing (..)
import Config
import Contracts.BucketSale.Wrappers exposing (ExitInfo)
import Element exposing (Attribute, Element)
import Element.Background
import Element.Border
import Element.Events
import Element.Font
import Element.Input
import Eth.Types exposing (Address)
import FormatFloat exposing (formatFloat)
import Helpers.Element as EH
import Helpers.Eth as EthHelpers
import Helpers.Time as TimeHelpers
import Html.Attributes
import Images
import List.Extra
import Maybe.Extra
import Result.Extra
import Routing
import Time
import TokenValue exposing (TokenValue)
import Wallet


root : Model -> ( Element Msg, List (Element Msg) )
root model =
    ( Element.column
        [ Element.width Element.fill
        , Element.paddingEach
            { bottom = 40
            , top = 0
            , right = 0
            , left = 0
            }
        ]
        [ case model.bucketSale of
            Nothing ->
                Element.el
                    [ Element.centerX
                    , Element.Font.size 30
                    , Element.Font.color EH.white
                    ]
                <|
                    Element.text "Loading..."

            Just (Err errStr) ->
                Element.el
                    [ Element.centerX
                    , Element.Font.size 30
                    , Element.Font.color EH.white
                    ]
                <|
                    Element.text errStr

            Just (Ok bucketSale) ->
                Element.row
                    [ Element.centerX
                    , Element.spacing 50
                    ]
                    [ closedBucketsPane model
                    , focusedBucketPane
                        bucketSale
                        (getFocusedBucketId
                            bucketSale
                            model.bucketView
                            model.now
                            model.testMode
                        )
                        model.wallet
                        model.enterUXModel
                        model.jurisdictionCheckStatus
                        model.trackedTxs
                        model.showReferralModal
                        model.now
                        model.testMode
                    , Element.column
                        [ Element.spacing 20
                        , Element.width Element.fill
                        ]
                        [ futureBucketsPane model bucketSale
                        , trackedTxsElement model.trackedTxs
                        ]
                    ]
        ]
    , viewModals model
    )


commonPaneAttributes : List (Attribute Msg)
commonPaneAttributes =
    [ Element.Background.color EH.white
    , Element.spacing 20
    , Element.Border.rounded 8
    , Element.centerY
    , Element.Border.shadow
        { offset = ( 0, 3 )
        , size = 0
        , blur = 20
        , color = Element.rgba 0 0 0 0.06
        }
    ]


closedBucketsPane : Model -> Element Msg
closedBucketsPane model =
    Element.column
        (commonPaneAttributes
            ++ [ Element.width <| Element.px 450
               , Element.paddingXY 32 25
               ]
        )
        [ Element.el
            [ Element.Font.size 25
            , Element.Font.bold
            ]
          <|
            Element.text "Concluded Buckets"
        , Element.paragraph
            [ Element.Font.color grayTextColor
            , Element.Font.size 15
            ]
            [ Element.text "These are the concluded buckets of FRY that have been claimed. If you have FRY to claim it will show below." ]
        , maybeUserBalanceBlock model.wallet model.userFryBalance
        , maybeClaimBlock model.wallet model.userExitInfo
        , totalExitedBlock model.totalTokensExited
        ]


focusedBucketPane : BucketSale -> Int -> Wallet.State -> EnterUXModel -> JurisdictionCheckStatus -> List TrackedTx -> Bool -> Time.Posix -> TestMode -> Element Msg
focusedBucketPane bucketSale bucketId wallet enterUXModel jurisdictionCheckStatus trackedTxs referralModalActive now testMode =
    Element.column
        (commonPaneAttributes
            ++ [ Element.width <| Element.px 780
               , Element.paddingXY 35 31
               , Element.spacing 7
               , Element.height <| Element.px 800
               ]
        )
        ([ focusedBucketHeaderEl
            bucketId
            (Wallet.userInfo wallet)
            enterUXModel.referrer
            referralModalActive
            testMode
         ]
            ++ (case getBucketInfo bucketSale bucketId now testMode of
                    InvalidBucket ->
                        [ Element.el
                            [ Element.Font.size 20
                            , Element.centerX
                            ]
                            (Element.text "Invalid bucket Id")
                        ]

                    ValidBucket bucketInfo ->
                        [ focusedBucketSubheaderEl bucketInfo
                        , focusedBucketTimeLeftEl
                            (getRelevantTimingInfo bucketInfo now testMode)
                            testMode
                        , enterBidUX wallet enterUXModel bucketInfo jurisdictionCheckStatus trackedTxs testMode
                        ]
               )
        )


futureBucketsPane : Model -> BucketSale -> Element Msg
futureBucketsPane model bucketSale =
    let
        fetchedNextBucketInfo =
            getBucketInfo
                bucketSale
                (getCurrentBucketId
                    bucketSale
                    model.now
                    model.testMode
                    + 1
                )
                model.now
                model.testMode
    in
    case fetchedNextBucketInfo of
        InvalidBucket ->
            noBucketsLeftBlock

        ValidBucket nextBucketInfo ->
            Element.column
                (commonPaneAttributes
                    ++ [ Element.width <| Element.px 450
                       , Element.paddingXY 32 25
                       ]
                )
                [ Element.el
                    [ Element.width Element.fill
                    , Element.Font.size 25
                    , Element.Font.bold
                    ]
                  <|
                    Element.text "Future Buckets"
                , Element.paragraph
                    [ Element.Font.color grayTextColor
                    , Element.Font.size 15
                    ]
                    [ Element.text "These are the upcoming buckets set to be released. The next bucket will begin in "
                    , emphasizedText PassiveStyle <|
                        TimeHelpers.toConciseIntervalString <|
                            TimeHelpers.sub
                                nextBucketInfo.bucketData.startTime
                                model.now
                    ]
                , maybeBucketsLeftBlock
                    bucketSale
                    model.now
                    model.testMode
                , maybeFryInFutureBucketsBlock
                    bucketSale
                    model.now
                    model.testMode
                ]


maybeUserBalanceBlock : Wallet.State -> Maybe TokenValue -> Element Msg
maybeUserBalanceBlock wallet maybeFryBalance =
    case ( Wallet.userInfo wallet, maybeFryBalance ) of
        ( Nothing, _ ) ->
            Element.none

        ( _, Nothing ) ->
            loadingElement

        ( Just userInfo, Just fryBalance ) ->
            sidepaneBlockContainer PassiveStyle
                [ bigNumberElement
                    [ Element.centerX ]
                    (TokenNum fryBalance)
                    "FRY"
                    PassiveStyle
                , Element.paragraph
                    [ Element.centerX
                    , Element.width Element.shrink
                    ]
                    [ Element.text "in your wallet"
                    ]
                ]


maybeClaimBlock : Wallet.State -> Maybe ExitInfo -> Element Msg
maybeClaimBlock wallet maybeExitInfo =
    case ( Wallet.userInfo wallet, maybeExitInfo ) of
        ( Nothing, _ ) ->
            Element.none

        ( _, Nothing ) ->
            loadingElement

        ( Just userInfo, Just exitInfo ) ->
            let
                ( blockStyle, maybeClaimButton ) =
                    if TokenValue.isZero exitInfo.totalExitable then
                        ( PassiveStyle, Nothing )

                    else
                        ( ActiveStyle, Just <| makeClaimButton userInfo exitInfo )
            in
            sidepaneBlockContainer blockStyle
                [ bigNumberElement
                    [ Element.centerX ]
                    (TokenNum exitInfo.totalExitable)
                    "FRY"
                    blockStyle
                , Element.paragraph
                    [ Element.centerX
                    , Element.width Element.shrink
                    ]
                    [ Element.text "available for "
                    , emphasizedText blockStyle "you"
                    , Element.text " to claim"
                    ]
                , Maybe.map
                    (Element.el [ Element.centerX ])
                    maybeClaimButton
                    |> Maybe.withDefault Element.none
                ]


totalExitedBlock : Maybe TokenValue -> Element Msg
totalExitedBlock maybeTotalExited =
    case maybeTotalExited of
        Nothing ->
            loadingElement

        Just totalExited ->
            sidepaneBlockContainer PassiveStyle
                [ bigNumberElement
                    [ Element.centerX ]
                    (TokenNum totalExited)
                    "FRY"
                    PassiveStyle
                , Element.paragraph
                    [ Element.centerX
                    , Element.width Element.shrink
                    ]
                    [ Element.text "disbursed "
                    , emphasizedText PassiveStyle "in total"
                    ]
                ]


focusedBucketHeaderEl : Int -> Maybe UserInfo -> Maybe Address -> Bool -> TestMode -> Element Msg
focusedBucketHeaderEl bucketId maybeUserInfo maybeReferrer referralModalActive testMode =
    Element.column
        [ Element.spacing 8
        , Element.width Element.fill
        ]
        [ Element.row
            [ Element.width Element.fill ]
            [ Element.row
                [ Element.Font.size 30
                , Element.Font.bold
                , Element.alignLeft
                , Element.spacing 10
                ]
                [ prevBucketArrow bucketId
                , Element.text <|
                    "Bucket #"
                        ++ String.fromInt bucketId
                , nextBucketArrow bucketId
                ]
            , maybeReferralIndicatorAndModal
                maybeUserInfo
                maybeReferrer
                referralModalActive
                testMode
            ]
        ]


maybeReferralIndicatorAndModal : Maybe UserInfo -> Maybe Address -> Bool -> TestMode -> Element Msg
maybeReferralIndicatorAndModal maybeUserInfo maybeReferrer referralModalActive testMode =
    case maybeUserInfo of
        Nothing ->
            Element.none

        Just userInfo ->
            Element.el
                [ Element.alignRight
                , Element.onRight <|
                    if referralModalActive then
                        Element.el
                            [ Element.alignLeft
                            , Element.moveRight 25
                            , Element.moveUp 50
                            , EH.moveToFront
                            ]
                            (referralModal userInfo maybeReferrer testMode)

                    else
                        Element.none
                , Element.inFront <|
                    if referralModalActive then
                        Element.el
                            [ EH.moveToFront ]
                        <|
                            referralBonusIndicator
                                (maybeReferrer /= Nothing)
                                True

                    else
                        Element.none
                ]
            <|
                referralBonusIndicator
                    (maybeReferrer /= Nothing)
                    referralModalActive


focusedBucketSubheaderEl : ValidBucketInfo -> Element Msg
focusedBucketSubheaderEl bucketInfo =
    case ( bucketInfo.bucketData.totalValueEntered, bucketInfo.bucketData.userBuy ) of
        ( Just totalValueEntered, Just userBuy ) ->
            Element.paragraph
                [ Element.Font.color grayTextColor
                , Element.Font.size 15
                ]
                [ emphasizedText PassiveStyle <|
                    TokenValue.toConciseString totalValueEntered
                , Element.text " DAI has been bid on this bucket so far. All bids are irreversible."
                ]

        _ ->
            loadingElement


nextBucketArrow : Int -> Element Msg
nextBucketArrow currentBucketId =
    Element.el
        [ Element.padding 4
        , Element.pointer
        , Element.Events.onClick (FocusToBucket (currentBucketId + 1))
        , Element.Font.extraBold
        ]
        (Element.text ">")


prevBucketArrow : Int -> Element Msg
prevBucketArrow currentBucketId =
    Element.el
        [ Element.padding 4
        , Element.pointer
        , Element.Events.onClick (FocusToBucket (currentBucketId - 1))
        , Element.Font.extraBold
        ]
        (Element.text "<")


focusedBucketTimeLeftEl : RelevantTimingInfo -> TestMode -> Element Msg
focusedBucketTimeLeftEl timingInfo testMode =
    Element.row
        [ Element.width Element.fill
        , Element.spacing 22
        ]
        [ progressBarElement (Element.rgba255 235 237 243 0.6) <|
            case timingInfo.state of
                Current ->
                    [ ( 1
                            - ((Time.posixToMillis timingInfo.relevantTimeFromNow |> toFloat)
                                / (Time.posixToMillis (Config.bucketSaleBucketInterval testMode) |> toFloat)
                              )
                      , Element.rgb255 255 0 120
                      )
                    ]

                _ ->
                    []
        , let
            intervalString =
                TimeHelpers.toConciseIntervalString timingInfo.relevantTimeFromNow
          in
          (Element.el
            [ Element.Font.color deepBlue ]
            << Element.text
          )
            (case timingInfo.state of
                Closed ->
                    "ended " ++ intervalString ++ " ago"

                Current ->
                    intervalString ++ " left"

                Future ->
                    "starts in " ++ intervalString
            )
        ]


enterBidUX : Wallet.State -> EnterUXModel -> ValidBucketInfo -> JurisdictionCheckStatus -> List TrackedTx -> TestMode -> Element Msg
enterBidUX wallet enterUXModel bucketInfo jurisdictionCheckStatus trackedTxs testMode =
    let
        miningEnters =
            trackedTxs
                |> List.filterMap
                    (\trackedTx ->
                        case ( trackedTx.action, trackedTx.status ) of
                            ( Enter enterInfo, Mining ) ->
                                Just enterInfo

                            _ ->
                                Nothing
                    )

        unlockMining =
            trackedTxs
                |> List.any
                    (\trackedTx ->
                        case trackedTx.action of
                            Unlock ->
                                trackedTx.status == Mining

                            _ ->
                                False
                    )
    in
    Element.column
        [ Element.width Element.fill
        , Element.spacing 20
        ]
        [ bidInputBlock enterUXModel bucketInfo testMode
        , bidImpactBlock enterUXModel bucketInfo miningEnters testMode
        , otherBidsImpactMsg
        , actionButton wallet enterUXModel bucketInfo unlockMining jurisdictionCheckStatus testMode
        ]


bidInputBlock : EnterUXModel -> ValidBucketInfo -> TestMode -> Element Msg
bidInputBlock enterUXModel bucketInfo testMode =
    centerpaneBlockContainer ActiveStyle
        [ emphasizedText ActiveStyle "I want to bid:"
        , Element.row
            [ Element.Background.color <| Element.rgba 1 1 1 0.08
            , Element.Border.rounded 4
            , Element.padding 13
            , Element.width Element.fill
            ]
            [ Element.Input.text
                [ Element.Font.size 19
                , Element.Font.medium
                , Element.Font.color EH.white
                , Element.Border.width 0
                , Element.width Element.fill
                , Element.Background.color EH.transparent
                ]
                { onChange = DaiInputChanged
                , text = enterUXModel.daiInput
                , placeholder =
                    Just <|
                        Element.Input.placeholder
                            [ Element.Font.medium
                            , Element.Font.color <| Element.rgba 1 1 1 0.25
                            ]
                            (Element.text "Enter Amount")
                , label = Element.Input.labelHidden "bid amount"
                }
            , Element.row
                [ Element.centerY
                , Element.spacing 10
                ]
                [ Images.daiSymbol
                    |> Images.toElement [ Element.height <| Element.px 30 ]
                , Element.text "DAI"
                ]
            ]
        , Maybe.map
            (\totalValueEntered ->
                pricePerTokenMsg
                    totalValueEntered
                    (enterUXModel.daiAmount
                        |> Maybe.map Result.toMaybe
                        |> Maybe.Extra.join
                    )
                    testMode
            )
            bucketInfo.bucketData.totalValueEntered
            |> Maybe.withDefault loadingElement
        ]


pricePerTokenMsg : TokenValue -> Maybe TokenValue -> TestMode -> Element Msg
pricePerTokenMsg totalValueEntered maybeDaiAmount testMode =
    Element.paragraph
        [ Element.Font.size 14
        , Element.Font.medium
        ]
        ([ Element.text <|
            "The current FRY price is "
                ++ (calcEffectivePricePerToken
                        totalValueEntered
                        testMode
                        |> TokenValue.toConciseString
                   )
                ++ " DAI/FRY."
         ]
            ++ (case maybeDaiAmount of
                    Just amount ->
                        [ Element.text " This bid will increase the price to "
                        , emphasizedText ActiveStyle <|
                            (calcEffectivePricePerToken
                                (TokenValue.add
                                    totalValueEntered
                                    amount
                                )
                                testMode
                                |> TokenValue.toConciseString
                            )
                                ++ " DAI/FRY."
                        ]

                    _ ->
                        []
               )
        )


bidImpactBlock : EnterUXModel -> ValidBucketInfo -> List EnterInfo -> TestMode -> Element Msg
bidImpactBlock enterUXModel bucketInfo miningEnters testMode =
    centerpaneBlockContainer PassiveStyle <|
        [ emphasizedText PassiveStyle "Your current bid standing:" ]
            ++ (case ( bucketInfo.bucketData.totalValueEntered, bucketInfo.bucketData.userBuy ) of
                    ( Just totalValueEntered, Just userBuy ) ->
                        let
                            existingUserBidAmount =
                                userBuy.valueEntered

                            miningUserBidAmount =
                                miningEnters
                                    |> List.map .amount
                                    |> List.foldl TokenValue.add TokenValue.zero

                            extraUserBidAmount =
                                enterUXModel.daiAmount
                                    |> Maybe.map Result.toMaybe
                                    |> Maybe.Extra.join
                                    |> Maybe.withDefault TokenValue.zero
                        in
                        [ bidImpactParagraphEl totalValueEntered ( existingUserBidAmount, miningUserBidAmount, extraUserBidAmount ) testMode
                        , bidBarEl totalValueEntered ( existingUserBidAmount, miningUserBidAmount, extraUserBidAmount ) testMode
                        ]

                    _ ->
                        [ loadingElement ]
               )


bidImpactParagraphEl : TokenValue -> ( TokenValue, TokenValue, TokenValue ) -> TestMode -> Element Msg
bidImpactParagraphEl totalValueEntered ( existingUserBidAmount, miningUserBidAmount, extraUserBidAmount ) testMode =
    let
        totalUserBidAmount =
            existingUserBidAmount
                |> TokenValue.add miningUserBidAmount
                |> TokenValue.add extraUserBidAmount

        para =
            Element.paragraph
                [ Element.width Element.fill
                , Element.Font.color grayTextColor
                ]

        existingUserBidsPara =
            para <|
                if TokenValue.isZero existingUserBidAmount then
                    [ Element.text "You haven't entered any bids into this bucket." ]

                else
                    [ Element.text "You have entered "
                    , emphasizedText PassiveStyle <|
                        TokenValue.toConciseString existingUserBidAmount
                            ++ " DAI"
                    , Element.text " into this bucket."
                    ]

        assumptionsBlock =
            let
                assumptionParasList =
                    [ if TokenValue.isZero miningUserBidAmount then
                        Nothing

                      else
                        Just <|
                            para <|
                                [ Element.text "your submitted bid of "
                                , emphasizedText PassiveStyle <|
                                    TokenValue.toConciseString miningUserBidAmount
                                        ++ " DAI"
                                , Element.text " is mined before this bucket ends"
                                ]
                    , if TokenValue.isZero extraUserBidAmount then
                        Nothing

                      else
                        Just <|
                            para <|
                                [ Element.text "you submit a further bid of "
                                , emphasizedText PassiveStyle <|
                                    TokenValue.toConciseString extraUserBidAmount
                                        ++ " DAI"
                                ]
                    ]
                        |> Maybe.Extra.values
            in
            if assumptionParasList == [] then
                Element.none

            else
                Element.column
                    [ Element.width Element.fill
                    , Element.spacing 5
                    ]
                    ([ para <|
                        [ Element.text "Assuming:" ]
                     ]
                        ++ (assumptionParasList
                                |> List.map
                                    (\p ->
                                        Element.row
                                            [ Element.width Element.fill
                                            , Element.spacing 10
                                            ]
                                            [ Element.text EH.bulletPointString
                                            , p
                                            ]
                                    )
                           )
                    )

        claimablePara =
            if TokenValue.isZero totalUserBidAmount then
                Element.none

            else
                para <|
                    [ Element.text "If no one else bids on this bucket before it ends, you will be able to claim "
                    , emphasizedText PassiveStyle <|
                        (calcClaimableTokens
                            (totalValueEntered
                                |> TokenValue.add miningUserBidAmount
                                |> TokenValue.add extraUserBidAmount
                            )
                            totalUserBidAmount
                            testMode
                            |> TokenValue.toConciseString
                        )
                            ++ " FRY"
                    , Element.text <|
                        " out of "
                            ++ TokenValue.toConciseString (Config.bucketSaleTokensPerBucket testMode)
                            ++ " FRY available."
                    ]
    in
    Element.column
        [ Element.width Element.fill
        , Element.spacing 10
        ]
    <|
        [ existingUserBidsPara
        , assumptionsBlock
        , claimablePara
        ]


bidBarEl : TokenValue -> ( TokenValue, TokenValue, TokenValue ) -> TestMode -> Element Msg
bidBarEl totalValueEntered ( existingUserBidAmount, miningUserBidAmount, extraUserBidAmount ) testMode =
    let
        totalValueEnteredAfterBidAndMining =
            totalValueEntered
                |> TokenValue.add miningUserBidAmount
                |> TokenValue.add extraUserBidAmount
    in
    if TokenValue.isZero totalValueEnteredAfterBidAndMining then
        Element.paragraph
            [ Element.width Element.fill
            , Element.Font.color grayTextColor
            ]
            [ Element.text "No one has entered any bids into this bucket yet." ]

    else
        let
            existingUserBidColor =
                deepBlue

            miningUserBidColor =
                purple

            extraUserBidColor =
                lightBlue
        in
        Element.column
            [ Element.width Element.fill
            , Element.spacing 10
            , Element.paddingXY 0 10
            ]
            [ Element.row
                [ Element.width Element.fill ]
                [ Element.column
                    [ Element.alignLeft
                    , Element.spacing 6
                    ]
                    [ Element.el [ Element.Font.color grayTextColor ] <| Element.text "Your bid"
                    , Element.row []
                        (([ ( existingUserBidAmount, existingUserBidColor )
                          , ( miningUserBidAmount, miningUserBidColor )
                          , ( extraUserBidAmount, extraUserBidColor )
                          ]
                            |> List.map
                                (\( t, color ) ->
                                    if TokenValue.isZero t then
                                        Nothing

                                    else
                                        Just ( t, color )
                                )
                            |> Maybe.Extra.values
                            |> List.map
                                (\( tokens, color ) ->
                                    Element.el
                                        [ Element.Font.color color ]
                                        (Element.text <| TokenValue.toConciseString tokens)
                                )
                            |> List.intersperse (Element.text " + ")
                         )
                            ++ [ Element.text " DAI" ]
                        )
                    ]
                , Element.column
                    [ Element.alignRight
                    , Element.spacing 6
                    ]
                    [ Element.el
                        [ Element.Font.color grayTextColor
                        , Element.alignRight
                        ]
                      <|
                        Element.text <|
                            if totalValueEntered /= totalValueEnteredAfterBidAndMining then
                                "Resulting total bids in bucket"

                            else
                                "Total bids in bucket"
                    , Element.el
                        [ Element.alignRight ]
                        (Element.text <|
                            TokenValue.toConciseString totalValueEnteredAfterBidAndMining
                                ++ " DAI"
                        )
                    ]
                ]
            , progressBarElement (Element.rgba 0 0 0 0.1)
                [ ( TokenValue.toFloatWithWarning existingUserBidAmount
                        / TokenValue.toFloatWithWarning totalValueEnteredAfterBidAndMining
                  , existingUserBidColor
                  )
                , ( TokenValue.toFloatWithWarning miningUserBidAmount
                        / TokenValue.toFloatWithWarning totalValueEnteredAfterBidAndMining
                  , miningUserBidColor
                  )
                , ( TokenValue.toFloatWithWarning extraUserBidAmount
                        / TokenValue.toFloatWithWarning totalValueEnteredAfterBidAndMining
                  , extraUserBidColor
                  )
                ]
            ]


otherBidsImpactMsg : Element Msg
otherBidsImpactMsg =
    centerpaneBlockContainer PassiveStyle
        [ emphasizedText PassiveStyle "If other bids ARE made:"
        , Element.paragraph
            [ Element.width Element.fill
            , Element.Font.color grayTextColor
            ]
            [ Element.text "The price per token will increase further, and the amount of FRY you can claim from the bucket will decrease proportionally. (For example, if the total bid amount doubles, the effective price per token will also double, and your amount of claimable tokens will halve.)" ]
        ]


actionButton : Wallet.State -> EnterUXModel -> ValidBucketInfo -> Bool -> JurisdictionCheckStatus -> TestMode -> Element Msg
actionButton wallet enterUXModel bucketInfo unlockMining jurisdictionCheckStatus testMode =
    case jurisdictionCheckStatus of
        Allowed ->
            case Wallet.userInfo wallet of
                Nothing ->
                    connectToWeb3Button wallet

                Just userInfo ->
                    let
                        unlockDaiButton =
                            EH.redButton
                                Desktop
                                [ Element.width Element.fill ]
                                [ "Unlock Dai" ]
                                UnlockDaiButtonClicked

                        continueButton daiAmount =
                            EH.redButton
                                Desktop
                                [ Element.width Element.fill ]
                                [ "Continue" ]
                                (EnterButtonClicked <|
                                    EnterInfo
                                        userInfo
                                        bucketInfo.id
                                        daiAmount
                                        enterUXModel.referrer
                                )

                        disabledContinueButton =
                            EH.disabledButton
                                Desktop
                                [ Element.width Element.fill ]
                                "Continue"
                                Nothing

                        inProgressMsg text =
                            Element.el
                                [ Element.centerX
                                , Element.Font.size 22
                                , Element.Font.italic
                                , Element.Font.color grayTextColor
                                ]
                                (Element.text text)
                    in
                    case enterUXModel.allowance of
                        Nothing ->
                            inProgressMsg "Fetching Dai unlock status..."

                        Just allowance ->
                            if enterUXModel.allowance == Just TokenValue.zero then
                                unlockDaiButton

                            else if unlockMining then
                                inProgressMsg "Mining Dai unlock..."

                            else
                                -- Allowance is loaded and nonzero, and we are not mining an Unlock
                                case enterUXModel.daiAmount of
                                    Just (Ok daiAmount) ->
                                        if TokenValue.compare daiAmount allowance /= GT then
                                            continueButton daiAmount

                                        else
                                            unlockDaiButton

                                    _ ->
                                        disabledContinueButton

        Checking ->
            Element.text "Pretending to check jurisdiction..."

        Excluded ->
            Debug.todo ""

        FetchError httpError ->
            Debug.todo ""


noBucketsLeftBlock : Element Msg
noBucketsLeftBlock =
    Element.text "There are no more future blocks."


maybeBucketsLeftBlock : BucketSale -> Time.Posix -> TestMode -> Element Msg
maybeBucketsLeftBlock bucketSale now testMode =
    let
        currentBucketId =
            getCurrentBucketId
                bucketSale
                now
                testMode
    in
    sidepaneBlockContainer PassiveStyle
        [ bigNumberElement
            [ Element.centerX ]
            (IntegerNum
                (Config.bucketSaleNumBuckets
                    - currentBucketId
                )
            )
            "buckets"
            PassiveStyle
        , Element.paragraph
            [ Element.centerX
            , Element.width Element.shrink
            ]
            [ Element.text "left to run" ]
        ]


maybeFryInFutureBucketsBlock : BucketSale -> Time.Posix -> TestMode -> Element Msg
maybeFryInFutureBucketsBlock bucketSale now testMode =
    let
        currentBucketId =
            getCurrentBucketId
                bucketSale
                now
                testMode
    in
    sidepaneBlockContainer PassiveStyle
        [ bigNumberElement
            [ Element.centerX ]
            (TokenNum
                (TokenValue.mul
                    (Config.bucketSaleTokensPerBucket testMode)
                    (Config.bucketSaleNumBuckets
                        - currentBucketId
                    )
                )
            )
            "FRY"
            PassiveStyle
        , Element.paragraph
            [ Element.centerX
            , Element.width Element.shrink
            ]
            [ Element.text "left to be sold" ]
        ]


trackedTxsElement : List TrackedTx -> Element Msg
trackedTxsElement trackedTxs =
    if List.length trackedTxs == 0 then
        Element.none

    else
        Element.column
            [ Element.Border.rounded 5
            , Element.Background.color <| Element.rgb 0.9 0.9 0.9
            , Element.spacing 14
            , Element.padding 10
            , Element.width Element.fill
            ]
            [ Element.el [ Element.Font.size 20 ] <|
                Element.text "Eth Transactions"
            , trackedTxsColumn trackedTxs
            ]


trackedTxsColumn : List TrackedTx -> Element Msg
trackedTxsColumn trackedTxs =
    Element.column
        [ Element.spacing 8
        , Element.padding 5
        ]
        (List.map trackedTxRow trackedTxs)


trackedTxRow : TrackedTx -> Element Msg
trackedTxRow trackedTx =
    Element.row
        [ Element.Font.color grayTextColor
        , Element.Font.size 12
        , Element.Border.width 1
        , Element.Border.color <| Element.rgb 0.8 0.8 0.8
        , Element.Background.color <| Element.rgb 0.95 0.95 0.95
        , Element.spacing 8
        , Element.padding 4
        , Element.Border.rounded 4
        ]
        [ Element.el
            [ Element.padding 5
            , Element.Border.rounded 4
            , Element.Background.color <| Element.rgb 0.8 0.8 0.8
            , Element.width <| Element.px 90
            ]
            (case trackedTx.status of
                Signing ->
                    Element.el
                        [ Element.centerX
                        , Element.Font.italic
                        ]
                    <|
                        Element.text "Signing"

                Broadcasting ->
                    Element.el
                        [ Element.centerX
                        , Element.Font.italic
                        ]
                    <|
                        Element.text "Broadcasting"

                Mining ->
                    Element.el
                        [ Element.centerX
                        , Element.Font.italic
                        ]
                    <|
                        Element.text "Mining"

                Mined ->
                    Element.el
                        [ Element.centerX
                        , Element.Font.bold
                        , Element.Font.color EH.green
                        ]
                    <|
                        Element.text "Mined"

                Failed ->
                    Element.el
                        [ Element.centerX
                        , Element.Font.color EH.softRed
                        , Element.Font.italic
                        , Element.Font.bold
                        ]
                    <|
                        Element.text "Failed"

                Rejected ->
                    Element.el
                        [ Element.centerX
                        , Element.Font.color EH.softRed
                        , Element.Font.italic
                        , Element.Font.bold
                        ]
                    <|
                        Element.text "Rejected"
            )
        , Element.el
            [ Element.width Element.fill
            , Element.clip
            ]
          <|
            Element.text <|
                makeDescription trackedTx.action
        ]


makeDescription : ActionData -> String
makeDescription action =
    case action of
        Unlock ->
            "Unlock DAI"

        Enter enterInfo ->
            "Bid on bucket "
                ++ String.fromInt enterInfo.bucketId
                ++ " with "
                ++ TokenValue.toConciseString enterInfo.amount
                ++ " DAI"

        Exit ->
            "Claim FRY"


viewModals : Model -> List (Element Msg)
viewModals model =
    [ case model.confirmModal of
        Just exitInfo ->
            continueConfirmModal exitInfo

        Nothing ->
            Element.none
    , if model.showReferralModal then
        EH.modal
            (Element.rgba 0 0 0 0.25)
            False
            CloseReferralModal
            CloseReferralModal
            Element.none

      else
        Element.none
    ]


continueConfirmModal : EnterInfo -> Element Msg
continueConfirmModal enterInfo =
    EH.closeableModal
        True
        [ Element.Border.rounded 6
        , Element.width <| Element.px 520
        ]
        (Element.column
            [ Element.padding 27
            , Element.spacing 20
            , Element.width Element.fill
            ]
            [ Element.column
                [ Element.width Element.fill
                , Element.spacing 15
                ]
                [ Element.el
                    [ Element.Font.bold
                    , Element.Font.size 30
                    , Element.Font.color <| Element.rgb255 1 31 52
                    ]
                    (Element.text "Just to Confirm...")
                , Element.paragraph
                    [ Element.Font.color grayTextColor
                    , Element.Font.size 16
                    ]
                    [ Element.text "I understand that this bid cannot be refunded, and that if other bids are entered before the bucket ends, the amount of FRY I will be able to claim from this bucket will decrease." ]
                ]
            , Element.column
                [ Element.width Element.fill
                , Element.spacing 15
                ]
                [ EH.redButton
                    Desktop
                    [ Element.width Element.fill ]
                    [ "Confirm & deposit "
                        ++ TokenValue.toConciseString enterInfo.amount
                        ++ " DAI"
                    ]
                    (ConfirmClicked enterInfo)
                , EH.grayButton
                    Desktop
                    [ Element.width Element.fill ]
                    [ "Cancel" ]
                    CancelClicked
                ]
            ]
        )
        NoOp
        CancelClicked
        False


referralBonusIndicator : Bool -> Bool -> Element Msg
referralBonusIndicator hasReferral focusedStyle =
    Element.el
        [ Element.paddingXY 16 7
        , Element.Font.bold
        , Element.Font.size 18
        , Element.pointer
        , Element.Events.onClick ReferralIndicatorClicked
        , Element.Background.color
            ((if hasReferral then
                green

              else
                red
             )
                |> EH.addAlpha
                    (if focusedStyle then
                        1

                     else
                        0.05
                    )
            )
        , Element.Font.color
            (if focusedStyle then
                EH.white

             else if hasReferral then
                green

             else
                red
            )
        ]
        (Element.text <|
            if hasReferral then
                "Referral Bonus Active"

            else
                "No Referral Bonus"
        )


referralModal : UserInfo -> Maybe Address -> TestMode -> Element Msg
referralModal userInfo maybeReferrer testMode =
    let
        highlightedText text =
            Element.el
                [ Element.behindContent <|
                    Element.el
                        [ Element.centerX
                        , Element.centerY
                        , Element.padding 1
                        , Element.Background.color green
                        , Element.Font.color EH.white
                        , Element.Border.rounded 2
                        ]
                        (Element.text text)
                ]
                (Element.text text)

        ( firstElsChunk, maybeSecondElsChunk ) =
            case maybeReferrer of
                Nothing ->
                    ( [ Element.paragraph
                            [ Element.Font.size 24
                            , Element.Font.bold
                            , Element.Font.color red
                            ]
                            [ Element.text "Oh no! You’ve haven’t got a referral bonus." ]
                      , Element.column
                            [ Element.spacing 20
                            , Element.width Element.fill
                            , Element.Font.size 18
                            ]
                            [ Element.paragraph []
                                [ Element.text "You're missing out on some nice bonuses! The referred user gets a "
                                , highlightedText "10% bonus"
                                , Element.text " bid into the next bucket, and the referrer is rewarded as well!"
                                ]
                            , Element.paragraph []
                                [ Element.text "If you haven’t been given a referral link you can generate one for yourself below." ]
                            ]
                      ]
                    , Just <|
                        [ Element.paragraph
                            [ Element.Font.size 24
                            , Element.Font.bold
                            , Element.Font.color deepBlue
                            ]
                            [ Element.text "Your Referral Link" ]
                        , EH.button
                            Desktop
                            [ Element.width Element.fill ]
                            ( deepBlue, deepBlueWithAlpha 0.8, deepBlueWithAlpha 0.6 )
                            EH.white
                            [ "Generate My Referral Link" ]
                            (GenerateReferralClicked userInfo.address)
                        ]
                    )

                Just referrer ->
                    if referrer == userInfo.address then
                        ( [ Element.paragraph
                                [ Element.Font.size 24
                                , Element.Font.bold
                                , Element.Font.color green
                                ]
                                [ Element.text "Nice! You're using your own referral link." ]
                          , Element.paragraph []
                                [ Element.text "This means you'll get both bonuses!" ]
                          ]
                        , Just <|
                            [ Element.paragraph
                                [ Element.Font.size 24
                                , Element.Font.bold
                                , Element.Font.color deepBlue
                                ]
                                [ Element.text "Your Referral Link" ]
                            , referralLinkElement referrer testMode
                            , referralLinkCopyButton
                            ]
                        )

                    else
                        ( [ Element.paragraph
                                [ Element.Font.size 24
                                , Element.Font.bold
                                , Element.Font.color green
                                ]
                                [ Element.text "Nice! You’ve got a referral bonus." ]
                          ]
                        , Nothing
                        )
    in
    Element.column
        [ Element.Border.rounded 6
        , Element.Background.color EH.white
        , Element.width <| Element.px 480
        ]
        [ Element.column
            [ Element.width Element.fill
            , Element.Border.widthEach
                { bottom = 1
                , top = 0
                , right = 0
                , left = 0
                }
            , Element.Border.dashed
            , Element.Border.color <| Element.rgb 0.5 0.5 0.5
            , Element.padding 30
            , Element.spacing 30
            ]
            firstElsChunk
        , Maybe.map
            (Element.column
                [ Element.width Element.fill
                , Element.padding 30
                , Element.spacing 30
                ]
            )
            maybeSecondElsChunk
            |> Maybe.withDefault Element.none
        ]


referralLinkElement : Address -> TestMode -> Element Msg
referralLinkElement referrerAddress testMode =
    Element.el
        [ Element.width Element.fill
        , Element.Background.color <| deepBlueWithAlpha 0.05
        , Element.paddingXY 0 15
        , Element.Font.color deepBlue
        , Element.Font.size 12
        , Element.clipX
        , Element.scrollbarX
        ]
        (Element.el
            [ EH.withIdAttribute "copyable-link" ]
         <|
            Element.text
                (Routing.FullRoute
                    testMode
                    Routing.Sale
                    (Just referrerAddress)
                    |> Routing.routeToString
                    |> (\path -> "https://daihard.exchange" ++ path)
                )
        )


referralLinkCopyButton : Element Msg
referralLinkCopyButton =
    EH.button
        Desktop
        [ Element.width Element.fill
        , Element.htmlAttribute <|
            Html.Attributes.attribute
                "data-clipboard-target"
                "#copyable-link"
        , Element.htmlAttribute <|
            Html.Attributes.class "link-copy-btn"
        ]
        ( deepBlue, deepBlueWithAlpha 0.8, deepBlueWithAlpha 0.6 )
        EH.white
        [ "Copy Link" ]
        NoOp


progressBarElement : Element.Color -> List ( Float, Element.Color ) -> Element Msg
progressBarElement bgColor ratiosAndColors =
    Element.row
        [ Element.width Element.fill
        , Element.Background.color bgColor
        , Element.Border.rounded 4
        , Element.height <| Element.px 8
        , Element.clip
        ]
    <|
        let
            leftoverRatio =
                1
                    - (ratiosAndColors
                        |> List.map Tuple.first
                        |> List.sum
                      )

            progressBarEls =
                ratiosAndColors
                    |> List.map
                        (\( ratio, color ) ->
                            Element.el
                                [ Element.width <| Element.fillPortion (ratio * 2000 |> floor)
                                , Element.Background.color color
                                , Element.height Element.fill
                                ]
                                Element.none
                        )
        in
        progressBarEls
            ++ [ Element.el
                    [ Element.width <| Element.fillPortion (leftoverRatio * 2000 |> floor) ]
                    Element.none
               ]


emphasizedText : CommonBlockStyle -> (String -> Element Msg)
emphasizedText styleType =
    Element.el
        (case styleType of
            ActiveStyle ->
                [ Element.Font.color EH.white ]

            PassiveStyle ->
                [ Element.Font.color deepBlue ]
        )
        << Element.text


type CommonBlockStyle
    = ActiveStyle
    | PassiveStyle


centerpaneBlockContainer : CommonBlockStyle -> List (Element Msg) -> Element Msg
centerpaneBlockContainer styleType =
    Element.column
        ([ Element.width Element.fill
         , Element.Border.rounded 4
         , Element.padding 20
         , Element.spacing 13
         , Element.Font.size 16
         ]
            ++ (case styleType of
                    ActiveStyle ->
                        [ Element.Background.color deepBlue
                        , Element.Font.color <| Element.rgba 1 1 1 0.6
                        ]

                    PassiveStyle ->
                        [ Element.Background.color gray ]
               )
        )


sidepaneBlockContainer : CommonBlockStyle -> List (Element Msg) -> Element Msg
sidepaneBlockContainer styleType =
    Element.column
        ([ Element.width Element.fill
         , Element.Border.rounded 4
         , Element.paddingXY 22 18
         , Element.spacing 16
         ]
            ++ (case styleType of
                    ActiveStyle ->
                        [ Element.Background.color deepBlue
                        , Element.Font.color <| Element.rgba 1 1 1 0.6
                        ]

                    PassiveStyle ->
                        [ Element.Background.color <| deepBlueWithAlpha 0.05
                        , Element.Font.color <| deepBlueWithAlpha 0.3
                        ]
               )
        )


type NumberVal
    = IntegerNum Int
    | TokenNum TokenValue


numberValToString : NumberVal -> String
numberValToString numberVal =
    case numberVal of
        IntegerNum intVal ->
            formatFloat 0 (toFloat intVal)

        TokenNum tokenValue ->
            TokenValue.toConciseString tokenValue


bigNumberElement : List (Attribute Msg) -> NumberVal -> String -> CommonBlockStyle -> Element Msg
bigNumberElement attributes numberVal numberLabel blockStyle =
    Element.el
        (attributes
            ++ [ Element.Font.size 27
               , Element.Font.bold
               , Element.Font.color
                    (case blockStyle of
                        ActiveStyle ->
                            EH.white

                        PassiveStyle ->
                            deepBlue
                    )
               ]
        )
        (Element.text
            (numberValToString numberVal
                ++ " "
                ++ numberLabel
            )
        )


makeClaimButton : UserInfo -> ExitInfo -> Element Msg
makeClaimButton userInfo exitInfo =
    EH.lightBlueButton
        Desktop
        [ Element.width Element.fill ]
        [ "Claim your FRY" ]
        (ClaimClicked userInfo exitInfo)


loadingElement : Element Msg
loadingElement =
    Element.text "Loading"


gray : Element.Color
gray =
    Element.rgb255 235 237 243


deepBlue : Element.Color
deepBlue =
    Element.rgb255 10 33 109


lightBlue : Element.Color
lightBlue =
    Element.rgb255 25 169 214


purple : Element.Color
purple =
    Element.rgb255 212 0 255


deepBlueWithAlpha : Float -> Element.Color
deepBlueWithAlpha a =
    deepBlue
        |> EH.addAlpha a


grayTextColor : Element.Color
grayTextColor =
    Element.rgba255 1 31 52 0.75


red : Element.Color
red =
    Element.rgb255 226 1 79


green : Element.Color
green =
    Element.rgb255 0 162 149


connectToWeb3Button : Wallet.State -> Element Msg
connectToWeb3Button wallet =
    let
        commonButtonStyles =
            [ Element.width Element.fill
            , Element.padding 17
            , Element.Border.rounded 4
            , Element.Font.size 20
            , Element.Font.semiBold
            , Element.Font.center
            , Element.Background.color EH.softRed
            , Element.Font.color EH.white
            , Element.pointer
            ]

        commonTextStyles =
            [ Element.Font.bold
            , Element.Font.italic
            , Element.Font.size 20
            , Element.Font.center
            , Element.padding 17
            ]
    in
    case wallet of
        Wallet.NoneDetected ->
            Element.el
                (commonTextStyles
                    ++ [ Element.Font.color EH.softRed ]
                )
                (Element.text "No web3 wallet found")

        Wallet.OnlyNetwork _ ->
            Element.el
                (commonButtonStyles
                    ++ [ Element.Events.onClick <| CmdUp CmdUp.Web3Connect ]
                )
                (Element.text "Connect to Wallet")

        Wallet.WrongNetwork ->
            Element.el
                (commonTextStyles
                    ++ [ Element.Font.color EH.softRed ]
                )
                (Element.text "Wrong network. Switch to ETH Mainnet.")

        Wallet.Active _ ->
            Element.el
                (commonTextStyles
                    ++ [ Element.Font.color EH.green ]
                )
                (Element.text "Wallet connected!")

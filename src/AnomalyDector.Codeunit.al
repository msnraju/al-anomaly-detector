codeunit 50100 "Anomaly Dector"
{
    var
        RequestUrlLbl: Label '%1/anomalydetector/v1.0/timeseries/entire/detect', Locked = true, Comment = '%1 = Endpoint';
        EndpointLbl: Label 'https://anomalydetector.cognitiveservices.azure.com', Locked = true;
        SubscriptionKeyLbl: Label 'XXXX95d2XXXX1ebaXXXX4fdbXXXX898', Locked = true;

    procedure FindAnomalies(BankAccountNo: Code[20]; FromDate: Date; ToDate: Date; AnomalyData: Dictionary of [Date, Decimal]): Boolean
    var
        TimeSeriesData: Dictionary of [Date, Decimal];
    begin
        ToTimeSeriesData(BankAccountNo, FromDate, ToDate, TimeSeriesData);
        exit(CheckAnomaly(TimeSeriesData, AnomalyData));
    end;

    local procedure ToTimeSeriesData(BankAccountNo: Code[20]; FromDate: Date; ToDate: Date; TimeSeriesData: Dictionary of [Date, Decimal])
    var
        BankAccountLedgerEntry: Record "Bank Account Ledger Entry";
        PrevValue: Decimal;
    begin
        BankAccountLedgerEntry.Reset();
        BankAccountLedgerEntry.SetRange("Bank Account No.", BankAccountNo);
        BankAccountLedgerEntry.SetRange("Posting Date", FromDate, ToDate);
        if BankAccountLedgerEntry.FindSet() then
            repeat
                if TimeSeriesData.Get(BankAccountLedgerEntry."Posting Date", PrevValue) then
                    TimeSeriesData.Set(BankAccountLedgerEntry."Posting Date", PrevValue + BankAccountLedgerEntry."Amount (LCY)")
                else
                    TimeSeriesData.Add(BankAccountLedgerEntry."Posting Date", BankAccountLedgerEntry."Amount (LCY)");
            until BankAccountLedgerEntry.Next() = 0;
    end;

    local procedure TimeSeriesDataToJson(TimeSeriesData: Dictionary of [Date, Decimal]): JsonObject
    var
        JTimeSeriesData: JsonObject;
        JSeriesItem: JsonObject;
        JSeriesItems: JsonArray;
        PostingDate: Date;
        Value: Decimal;
    begin
        foreach PostingDate in TimeSeriesData.Keys do begin
            TimeSeriesData.Get(PostingDate, Value);
            JSeriesItem.Add('timestamp', Format(PostingDate, 0, 9));
            JSeriesItem.Add('value', Format(Value, 0, 9));

            JSeriesItems.Add(JSeriesItem);
        end;

        JTimeSeriesData.Add('series', JSeriesItems);
        JTimeSeriesData.Add('maxAnomalyRatio', 0.25);
        JTimeSeriesData.Add('sensitivity', 95);
        JTimeSeriesData.Add('granularity', 'daily');
        exit(JTimeSeriesData);
    end;

    local procedure CheckAnomaly(TimeSeriesData: Dictionary of [Date, Decimal]; AnomalyData: Dictionary of [Date, Decimal]): Boolean
    var
        JTimeSeriesData: JsonObject;
        JResponse: JsonObject;
    begin
        JTimeSeriesData := TimeSeriesDataToJson(TimeSeriesData);
        if not GetAPIResponse(JTimeSeriesData, JResponse) then
            exit;

        exit(AnomalyValuesToDataSet(JResponse, TimeSeriesData, AnomalyData));
    end;

    local procedure AnomalyValuesToDataSet(JResponse: JsonObject; TimeSeriesData: Dictionary of [Date, Decimal]; AnomalyData: Dictionary of [Date, Decimal]): Boolean
    var
        JAnomalyValues: JsonArray;
        JToken: JsonToken;
        Index: Integer;
        PostingDate: Date;
        Amount: Decimal;
    begin
        if not JResponse.Get('isAnomaly', JToken) then
            exit(false);

        JAnomalyValues := JToken.AsArray();
        foreach JToken in JAnomalyValues do begin
            Index += 1;

            if JToken.AsValue().AsBoolean() then begin
                TimeSeriesData.Keys.Get(Index, PostingDate);
                TimeSeriesData.Get(PostingDate, Amount);
                AnomalyData.Add(PostingDate, Amount);
            end;
        end;

        exit(true);
    end;

    local procedure GetAPIResponse(JTimeSeriesData: JsonObject; JResponse: JsonObject): Boolean
    var
        HttpClient: HttpClient;
        RequestHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
        ReqHttpContent: HttpContent;
        ResHttpResponseMessage: HttpResponseMessage;
        ContentTypeValues: array[1024] of Text;
        JsonText: Text;
        Url: Text;
    begin
        RequestHeaders := HttpClient.DefaultRequestHeaders();
        RequestHeaders.Add('Ocp-Apim-Subscription-Key', SubscriptionKeyLbl);

        JTimeSeriesData.WriteTo(JsonText);
        ReqHttpContent.WriteFrom(JsonText);
        ReqHttpContent.GetHeaders(ContentHeaders);
        if ContentHeaders.GetValues('Content-Type', ContentTypeValues) then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        Url := StrSubstNo(RequestUrlLbl, EndpointLbl);
        if not HttpClient.Post(Url, ReqHttpContent, ResHttpResponseMessage) then
            exit;

        if not ResHttpResponseMessage.IsSuccessStatusCode() then
            exit;

        ResHttpResponseMessage.Content.ReadAs(JsonText);
        JResponse.ReadFrom(JsonText);
        exit(true);
    end;
}
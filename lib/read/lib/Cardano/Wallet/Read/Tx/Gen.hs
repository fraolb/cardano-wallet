module Cardano.Wallet.Read.Tx.Gen where

import Prelude

import Cardano.Wallet.Read.Eras.EraFun
    ( EraFun (..)
    )
import Cardano.Wallet.Read.Tx
    ( Tx (..)
    )
import Cardano.Wallet.Read.Tx.Gen.Byron
    ( mkByronTx
    )
import Cardano.Wallet.Read.Tx.Gen.TxParameters
    ( TxParameters
    )
import Generics.SOP
    ( K
    , unK
    )

mkTxEra :: EraFun (K TxParameters) Tx
mkTxEra =
    EraFun
        { byronFun = g mkByronTx
        , shelleyFun = g mkShelleyTx
        , allegraFun = g mkAllegraTx
        , maryFun = g mkMaryTx
        , alonzoFun = g mkAlonzoTx
        , babbageFun = g mkBabbageTx
        , conwayFun = g mkConwayTx
        }
  where
    g f = Tx . f . unK

mkShelleyTx :: t
mkShelleyTx = error "Not implemented"

mkAllegraTx :: t
mkAllegraTx = error "Not implemented"

mkMaryTx :: t
mkMaryTx = error "Not implemented"

mkAlonzoTx :: t
mkAlonzoTx = error "Not implemented"

mkBabbageTx :: t
mkBabbageTx = error "Not implemented"

mkConwayTx :: t
mkConwayTx = error "Not implemented"

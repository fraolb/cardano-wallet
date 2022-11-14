# frozen_string_literal: true

RSpec.describe 'Cardano Wallet E2E tests - Shared wallets', :all, :e2e do
  before(:all) do
    # shelley wallets
    @wid = create_fixture_wallet(:shelley)
    @target_id = create_target_wallet(:shelley)

    # shared wallets
    @wid_sha = create_target_wallet(:shared)

    @nightly_shared_wallets = [@wid_sha]
    @nightly_shelley_wallets = [@wid, @target_id]
    wait_for_all_shelley_wallets(@nightly_shelley_wallets)
    wait_for_all_shared_wallets(@nightly_shared_wallets)
  end

  after(:each) do
    teardown
  end

  after(:all) do
    SHELLEY.stake_pools.quit(@target_id, PASS)
  end

  describe 'E2E Shared' do
    describe 'E2E Construct -> Sign -> Submit', :shared do
      it 'I can get min_utxo_value when contructing tx' do
        amt = 1
        tx_constructed = SHARED.transactions.construct(@wid_sha, payment_payload(amt))
        expect(tx_constructed.code).to eq 403
        expect(tx_constructed['code']).to eq 'utxo_too_small'
        required_minimum = tx_constructed['info']['tx_output_lovelace_required_minimum']['quantity']

        tx_constructed = SHARED.transactions.construct(@wid_sha, payment_payload(required_minimum))
        expect(tx_constructed).to be_correct_and_respond 202
      end

      it 'Single output transaction' do
        amt = MIN_UTXO_VALUE_PURE_ADA * 2
        address = SHELLEY.addresses.list(@target_id)[1]['id']
        target_before = get_shelley_balances(@target_id)
        src_before = get_shared_balances(@wid_sha)

        tx_constructed = SHARED.transactions.construct(@wid_sha, payment_payload(amt, address))
        expect(tx_constructed).to be_correct_and_respond 202
        expected_fee = tx_constructed['fee']['quantity']

        # Can be decoded
        tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
        expect(tx_decoded).to be_correct_and_respond 202

        expect(tx_decoded['id'].size).to be 64
        decoded_fee = tx_decoded['fee']['quantity']
        expect(expected_fee).to eq decoded_fee
        # inputs are ours
        expect(tx_decoded['inputs'].to_s).to include 'address'
        expect(tx_decoded['inputs'].to_s).to include 'amount'
        expect(tx_decoded['outputs']).not_to eq []
        expect(tx_decoded['script_validity']).to eq 'valid'
        expect(tx_decoded['validity_interval']['invalid_before']).to eq({ 'quantity' => 0, 'unit' => 'slot' })
        expect(tx_decoded['validity_interval']['invalid_hereafter']['quantity']).to be > 0
        expect(tx_decoded['collateral']).to eq []
        expect(tx_decoded['collateral_outputs']).to eq []
        expect(tx_decoded['metadata']).to eq nil
        expect(tx_decoded['deposits_taken']).to eq []
        expect(tx_decoded['deposits_returned']).to eq []
        expect(tx_decoded['withdrawals']).to eq []
        expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
        expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
        expect(tx_decoded['certificates']).to eq []

        tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
        expect(tx_signed).to be_correct_and_respond 202

        tx_submitted = SHARED.transactions.submit(@wid_sha, tx_signed['transaction'])
        expect(tx_submitted).to be_correct_and_respond 202

        tx_id = tx_submitted['id']
        # TODO: ADP-2224: change to wait_for_tx_in_ledger(@wid_sha, tx_id)
        eventually "Funds are on target wallet: #{@target_id}" do
          available = SHELLEY.wallets.get(@target_id)['balance']['available']['quantity']
          total = SHELLEY.wallets.get(@target_id)['balance']['total']['quantity']
          (available == amt + target_before['available']) &&
            (total == amt + target_before['total'])
        end

        target_after = get_shelley_balances(@target_id)
        src_after = get_shared_balances(@wid_sha)

        verify_ada_balance(src_after, src_before,
                           target_after, target_before,
                           amt, expected_fee)
        # tx history
        # TODO ADP-2224: check tx history on src wallet
        # on target wallet
        txt = SHELLEY.transactions.get(@target_id, tx_id)
        tx_amount(txt, amt)
        tx_fee(txt, 0)
        tx_inputs(txt, present: true)
        tx_outputs(txt, present: true)
        tx_direction(txt, 'incoming')
        tx_script_validity(txt, 'valid')
        tx_status(txt, 'in_ledger')
        tx_collateral(txt, present: false)
        tx_collateral_outputs(txt, present: false)
        tx_metadata(txt, nil)
        tx_deposits(txt, deposit_taken: 0, deposit_returned: 0)
        tx_withdrawals(txt, present: false)
        tx_mint_burn(txt, mint: [], burn: [])
        tx_extra_signatures(txt, present: false)
        tx_script_integrity(txt, present: false)
        tx_validity_interval_default(txt)
        tx_certificates(txt, present: false)
      end

      it 'Multi output transaction' do
        amt = MIN_UTXO_VALUE_PURE_ADA
        address = SHELLEY.addresses.list(@target_id)[1]['id']
        target_before = get_shelley_balances(@target_id)
        src_before = get_shared_balances(@wid_sha)

        payment = [{ address: address,
                     amount: { quantity: amt,
                               unit: 'lovelace' } },
                   { address: address,
                     amount: { quantity: amt,
                               unit: 'lovelace' } }]
        tx_constructed = SHARED.transactions.construct(@wid_sha, payment)
        expect(tx_constructed).to be_correct_and_respond 202
        expected_fee = tx_constructed['fee']['quantity']

        # Can be decoded
        tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
        expect(tx_decoded).to be_correct_and_respond 202

        expect(tx_decoded['id'].size).to be 64
        decoded_fee = tx_decoded['fee']['quantity']
        expect(expected_fee).to eq decoded_fee
        # inputs are ours
        expect(tx_decoded['inputs'].to_s).to include 'address'
        expect(tx_decoded['inputs'].to_s).to include 'amount'
        expect(tx_decoded['outputs']).not_to eq []
        expect(tx_decoded['script_validity']).to eq 'valid'
        expect(tx_decoded['validity_interval']['invalid_before']).to eq({ 'quantity' => 0, 'unit' => 'slot' })
        expect(tx_decoded['validity_interval']['invalid_hereafter']['quantity']).to be > 0
        expect(tx_decoded['collateral']).to eq []
        expect(tx_decoded['collateral_outputs']).to eq []
        expect(tx_decoded['metadata']).to eq nil
        expect(tx_decoded['deposits_taken']).to eq []
        expect(tx_decoded['deposits_returned']).to eq []
        expect(tx_decoded['withdrawals']).to eq []
        expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
        expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
        expect(tx_decoded['certificates']).to eq []

        tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
        expect(tx_signed).to be_correct_and_respond 202

        tx_submitted = SHARED.transactions.submit(@wid_sha, tx_signed['transaction'])
        expect(tx_submitted).to be_correct_and_respond 202

        tx_id = tx_submitted['id']
        # TODO: ADP-2224: change to wait_for_tx_in_ledger(@wid_sha, tx_id)
        eventually "Funds are on target wallet: #{@target_id}" do
          available = SHELLEY.wallets.get(@target_id)['balance']['available']['quantity']
          total = SHELLEY.wallets.get(@target_id)['balance']['total']['quantity']
          (available == (amt * 2) + target_before['available']) &&
            (total == (amt * 2) + target_before['total'])
        end

        target_after = get_shelley_balances(@target_id)
        src_after = get_shared_balances(@wid_sha)

        verify_ada_balance(src_after, src_before,
                           target_after, target_before,
                           amt * 2, expected_fee)
        # tx history
        # TODO ADP-2224: check tx history on src wallet
        # on target wallet
        txt = SHELLEY.transactions.get(@target_id, tx_id)
        tx_amount(txt, amt * 2)
        tx_fee(txt, 0)
        tx_inputs(txt, present: true)
        tx_outputs(txt, present: true)
        tx_direction(txt, 'incoming')
        tx_script_validity(txt, 'valid')
        tx_status(txt, 'in_ledger')
        tx_collateral(txt, present: false)
        tx_collateral_outputs(txt, present: false)
        tx_metadata(txt, nil)
        tx_deposits(txt, deposit_taken: 0, deposit_returned: 0)
        tx_withdrawals(txt, present: false)
        tx_mint_burn(txt, mint: [], burn: [])
        tx_extra_signatures(txt, present: false)
        tx_script_integrity(txt, present: false)
        tx_validity_interval_default(txt)
        tx_certificates(txt, present: false)
      end

      it 'Multi-assets transaction' do
        amt = 1
        amt_ada = 1_600_000
        address = SHELLEY.addresses.list(@target_id)[1]['id']
        target_before = get_shelley_balances(@target_id)
        src_before = get_shared_balances(@wid_sha)

        payment = [{ 'address' => address,
                     'amount' => { 'quantity' => amt_ada, 'unit' => 'lovelace' },
                     'assets' => [{ 'policy_id' => ASSETS[0]['policy_id'],
                                    'asset_name' => ASSETS[0]['asset_name'],
                                    'quantity' => amt },
                                  { 'policy_id' => ASSETS[1]['policy_id'],
                                    'asset_name' => ASSETS[1]['asset_name'],
                                    'quantity' => amt }] }]
        tx_constructed = SHARED.transactions.construct(@wid_sha, payment)
        expect(tx_constructed).to be_correct_and_respond 202
        expected_fee = tx_constructed['fee']['quantity']

        # Can be decoded
        tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
        expect(tx_decoded).to be_correct_and_respond 202

        expect(tx_decoded['id'].size).to be 64
        decoded_fee = tx_decoded['fee']['quantity']
        expect(expected_fee).to eq decoded_fee
        # inputs are ours
        expect(tx_decoded['inputs'].to_s).to include 'address'
        expect(tx_decoded['inputs'].to_s).to include 'amount'
        expect(tx_decoded['outputs']).not_to eq []
        expect(tx_decoded['script_validity']).to eq 'valid'
        expect(tx_decoded['validity_interval']['invalid_before']).to eq({ 'quantity' => 0, 'unit' => 'slot' })
        expect(tx_decoded['validity_interval']['invalid_hereafter']['quantity']).to be > 0
        expect(tx_decoded['collateral']).to eq []
        expect(tx_decoded['collateral_outputs']).to eq []
        expect(tx_decoded['metadata']).to eq nil
        expect(tx_decoded['deposits_taken']).to eq []
        expect(tx_decoded['deposits_returned']).to eq []
        expect(tx_decoded['withdrawals']).to eq []
        expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
        expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
        expect(tx_decoded['certificates']).to eq []

        tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
        expect(tx_signed).to be_correct_and_respond 202

        # ADP-2221 [SharedWallets] FeeTooSmallUTxO when submitting transaction from Shared wallet
        tx_submitted = SHARED.transactions.submit(@wid_sha, tx_signed['transaction'])
        expect(tx_submitted).to be_correct_and_respond 202

        tx_id = tx_submitted['id']
        # TODO: ADP-2224: change to wait_for_tx_in_ledger(@wid_sha, tx_id)
        eventually "Funds are on target wallet: #{@target_id}" do
          available = SHELLEY.wallets.get(@target_id)['balance']['available']['quantity']
          total = SHELLEY.wallets.get(@target_id)['balance']['total']['quantity']
          (available == amt_ada + target_before['available']) &&
            (total == amt_ada + target_before['total'])
        end

        target_after = get_shelley_balances(@target_id)
        src_after = get_shared_balances(@wid_sha)

        verify_ada_balance(src_after, src_before,
                           target_after, target_before,
                           amt_ada, expected_fee)

        verify_asset_balance(src_after, src_before,
                             target_after, target_before,
                             amt)
        # tx history
        # TODO ADP-2224: check tx history on src wallet
        # on target wallet
        txt = SHELLEY.transactions.get(@target_id, tx_id)
        tx_amount(txt, amt_ada)
        tx_fee(txt, 0)
        tx_inputs(txt, present: true)
        tx_outputs(txt, present: true)
        tx_direction(txt, 'incoming')
        tx_script_validity(txt, 'valid')
        tx_status(txt, 'in_ledger')
        tx_collateral(txt, present: false)
        tx_collateral_outputs(txt, present: false)
        tx_metadata(txt, nil)
        tx_deposits(txt, deposit_taken: 0, deposit_returned: 0)
        tx_withdrawals(txt, present: false)
        tx_mint_burn(txt, mint: [], burn: [])
        tx_extra_signatures(txt, present: false)
        tx_script_integrity(txt, present: false)
        tx_validity_interval_default(txt)
        tx_certificates(txt, present: false)
      end

      it 'Validity intervals' do
        amt = MIN_UTXO_VALUE_PURE_ADA
        address = SHELLEY.addresses.list(@target_id)[1]['id']
        target_before = get_shelley_balances(@target_id)
        src_before = get_shared_balances(@wid_sha)
        inv_before = 500
        inv_hereafter = 5_000_000_000
        validity_interval = { 'invalid_before' => { 'quantity' => inv_before, 'unit' => 'slot' },
                              'invalid_hereafter' => { 'quantity' => inv_hereafter, 'unit' => 'slot' } }
        tx_constructed = SHARED.transactions.construct(@wid_sha,
                                                       payment_payload(amt, address),
                                                       nil, # withdrawal
                                                       nil, # metadata
                                                       nil, # delegations
                                                       nil, # mint_burn
                                                       validity_interval)
        expect(tx_constructed).to be_correct_and_respond 202
        expected_fee = tx_constructed['fee']['quantity']

        # Can be decoded
        tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
        expect(tx_decoded).to be_correct_and_respond 202

        expect(tx_decoded['id'].size).to be 64
        decoded_fee = tx_decoded['fee']['quantity']
        expect(expected_fee).to eq decoded_fee
        # inputs are ours
        expect(tx_decoded['inputs'].to_s).to include 'address'
        expect(tx_decoded['inputs'].to_s).to include 'amount'
        expect(tx_decoded['outputs']).not_to eq []
        expect(tx_decoded['script_validity']).to eq 'valid'
        expect(tx_decoded['validity_interval']['invalid_before']).to eq validity_interval['invalid_before']
        expect(tx_decoded['validity_interval']['invalid_hereafter']).to eq validity_interval['invalid_hereafter']
        expect(tx_decoded['collateral']).to eq []
        expect(tx_decoded['collateral_outputs']).to eq []
        expect(tx_decoded['metadata']).to eq nil
        expect(tx_decoded['deposits_taken']).to eq []
        expect(tx_decoded['deposits_returned']).to eq []
        expect(tx_decoded['withdrawals']).to eq []
        expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
        expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
        expect(tx_decoded['certificates']).to eq []

        tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
        expect(tx_signed).to be_correct_and_respond 202

        # ADP-2221 [SharedWallets] FeeTooSmallUTxO when submitting transaction from Shared wallet
        tx_submitted = SHARED.transactions.submit(@wid_sha, tx_signed['transaction'])
        expect(tx_submitted).to be_correct_and_respond 202

        tx_id = tx_submitted['id']
        # TODO: ADP-2224: change to wait_for_tx_in_ledger(@wid_sha, tx_id)
        eventually "Funds are on target wallet: #{@target_id}" do
          available = SHELLEY.wallets.get(@target_id)['balance']['available']['quantity']
          total = SHELLEY.wallets.get(@target_id)['balance']['total']['quantity']
          (available == amt + target_before['available']) &&
            (total == amt + target_before['total'])
        end

        target_after = get_shelley_balances(@target_id)
        src_after = get_shared_balances(@wid_sha)

        verify_ada_balance(src_after, src_before,
                           target_after, target_before,
                           amt, expected_fee)
        # tx history
        # TODO ADP-2224: check tx history on src wallet
        # on target wallet
        txt = SHELLEY.transactions.get(@target_id, tx_id)
        tx_amount(txt, amt)
        tx_fee(txt, 0)
        tx_inputs(txt, present: true)
        tx_outputs(txt, present: true)
        tx_direction(txt, 'incoming')
        tx_script_validity(txt, 'valid')
        tx_status(txt, 'in_ledger')
        tx_collateral(txt, present: false)
        tx_collateral_outputs(txt, present: false)
        tx_metadata(txt, nil)
        tx_deposits(txt, deposit_taken: 0, deposit_returned: 0)
        tx_withdrawals(txt, present: false)
        tx_mint_burn(txt, mint: [], burn: [])
        tx_extra_signatures(txt, present: false)
        tx_script_integrity(txt, present: false)
        tx_validity_interval(txt, invalid_before: inv_before, invalid_hereafter: inv_hereafter)
        tx_certificates(txt, present: false)
      end

      it 'Only metadata (without submitting)' do
        # We can submit such tx, but cannot tell when tx is actually in ledger
        # (as we cannot get tx history (ADP-2224))
        metadata = METADATA
        # balance = get_shared_balances(@wid_sha)
        tx_constructed = SHARED.transactions.construct(@wid_sha,
                                                       nil, # payments
                                                       nil, # withdrawal
                                                       metadata)
        expect(tx_constructed).to be_correct_and_respond 202
        expected_fee = tx_constructed['fee']['quantity']

        # Can be decoded
        tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
        expect(tx_decoded).to be_correct_and_respond 202

        expect(tx_decoded['id'].size).to be 64
        decoded_fee = tx_decoded['fee']['quantity']
        expect(expected_fee).to eq decoded_fee
        # inputs are ours
        expect(tx_decoded['inputs'].to_s).to include 'address'
        expect(tx_decoded['inputs'].to_s).to include 'amount'
        expect(tx_decoded['outputs']).not_to eq []
        expect(tx_decoded['script_validity']).to eq 'valid'
        expect(tx_decoded['validity_interval']['invalid_before']).to eq({ 'quantity' => 0, 'unit' => 'slot' })
        expect(tx_decoded['validity_interval']['invalid_hereafter']['quantity']).to be > 0
        expect(tx_decoded['collateral']).to eq []
        expect(tx_decoded['collateral_outputs']).to eq []
        expect(tx_decoded['metadata']).to eq metadata
        expect(tx_decoded['deposits_taken']).to eq []
        expect(tx_decoded['deposits_returned']).to eq []
        expect(tx_decoded['withdrawals']).to eq []
        expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
        expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
        expect(tx_decoded['certificates']).to eq []

        tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
        expect(tx_signed).to be_correct_and_respond 202

        # TODO: ADP-2224: cannot tell when tx is actually in ledger, so this needs
        # to be commented for now, because of potential race conditions with subsequent tests
        # tx_submitted = SHARED.transactions.submit(@wid_sha, tx_signed["transaction"])
        # expect(tx_submitted).to be_correct_and_respond 202
        # tx_id = tx_submitted['id']

        # TODO: ADP-2224: change to wait_for_tx_in_ledger(@wid_sha, tx_id)
        # TODO ADP-2224: check tx history on src wallet and metadata is there
      end

      it 'Delegation (without submitting)' do
        # Delegation not yet implemented, only construct and sign in this tc
        # balance = get_shared_balances(@wid_sha)
        expected_deposit = CARDANO_CLI.protocol_params['stakeAddressDeposit']
        puts "Expected deposit #{expected_deposit}"

        # Pick up pool id to join
        pools = SHELLEY.stake_pools
        pool_id = pools.list({ stake: 1000 }).sample['id']

        # Join pool
        delegation = [{
          'join' => {
            'pool' => pool_id,
            'stake_key_index' => '0H'
          }
        }]

        tx_constructed = SHARED.transactions.construct(@wid_sha,
                                                       nil, # payment
                                                       nil, # withdrawal
                                                       nil, # metadata
                                                       delegation,
                                                       nil, # mint_burn
                                                       nil) # validity_interval
        # Check fee and deposit on joining
        tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
        expect(tx_decoded).to be_correct_and_respond 202

        # TODO: although you can construct and decode delegation, deposit_taken /deposit_returned are not shown atm
        # deposit_taken = tx_constructed['coin_selection']['deposits_taken'].first['quantity']
        # decoded_deposit_taken = tx_decoded['deposits_taken'].first['quantity']
        # expect(deposit_taken).to eq decoded_deposit_taken
        # expect(deposit_taken).to eq expected_deposit

        expected_fee = tx_constructed['fee']['quantity']
        decoded_fee = tx_decoded['fee']['quantity']
        expect(decoded_fee).to eq expected_fee
        # inputs are ours
        expect(tx_decoded['inputs'].to_s).to include 'address'
        expect(tx_decoded['inputs'].to_s).to include 'amount'
        expect(tx_decoded['outputs']).not_to eq []
        expect(tx_decoded['script_validity']).to eq 'valid'
        expect(tx_decoded['validity_interval']['invalid_before']).to eq({ 'quantity' => 0, 'unit' => 'slot' })
        expect(tx_decoded['validity_interval']['invalid_hereafter']['quantity']).to be > 0
        expect(tx_decoded['collateral']).to eq []
        expect(tx_decoded['collateral_outputs']).to eq []
        expect(tx_decoded['metadata']).to eq nil
        expect(tx_decoded['deposits_taken']).to eq []
        expect(tx_decoded['deposits_returned']).to eq []
        expect(tx_decoded['withdrawals']).to eq []
        expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
        expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
        expect(tx_decoded['certificates']).to eq []

        tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
        expect(tx_signed).to be_correct_and_respond 202
      end

      describe 'Minting and Burning' do
        it 'Can mint and then burn (without submitting)' do
          # Minting and Burning not yet implemented, only construct and sign in this tc
          # src_before = get_shared_balances(@wid_sha)
          policy_script1 = 'cosigner#0'
          policy_script2 = { 'all' => ['cosigner#0'] }
          policy_script3 = { 'any' => ['cosigner#0'] }

          # Minting:
          mint = [mint(asset_name('Token1'), 1000, policy_script1),
                  mint(asset_name('Token2'), 1000, policy_script2),
                  mint('', 1000, policy_script3)]

          tx_constructed = SHARED.transactions.construct(@wid_sha,
                                                         nil, # payment
                                                         nil, # withdrawal
                                                         nil, # metadata
                                                         nil, # delegation
                                                         mint)
          expect(tx_constructed).to be_correct_and_respond 202

          tx_decoded = SHARED.transactions.decode(@wid_sha, tx_constructed['transaction'])
          expect(tx_decoded).to be_correct_and_respond 202

          expected_fee = tx_constructed['fee']['quantity']
          decoded_fee = tx_decoded['fee']['quantity']
          expect(expected_fee).to eq decoded_fee
          # inputs are ours
          expect(tx_decoded['inputs'].to_s).to include 'address'
          expect(tx_decoded['inputs'].to_s).to include 'amount'
          expect(tx_decoded['outputs']).not_to eq []
          expect(tx_decoded['script_validity']).to eq 'valid'
          expect(tx_decoded['validity_interval']['invalid_before']).to eq({ 'quantity' => 0, 'unit' => 'slot' })
          expect(tx_decoded['validity_interval']['invalid_hereafter']['quantity']).to be > 0
          expect(tx_decoded['collateral']).to eq []
          expect(tx_decoded['collateral_outputs']).to eq []
          expect(tx_decoded['metadata']).to eq nil
          expect(tx_decoded['deposits_taken']).to eq []
          expect(tx_decoded['deposits_returned']).to eq []
          expect(tx_decoded['withdrawals']).to eq []
          # TODO: mint / burn currently not decoded
          expect(tx_decoded['mint']).to eq({ 'tokens' => [] })
          expect(tx_decoded['burn']).to eq({ 'tokens' => [] })
          expect(tx_decoded['certificates']).to eq []

          tx_signed = SHARED.transactions.sign(@wid_sha, PASS, tx_constructed['transaction'])
          expect(tx_signed).to be_correct_and_respond 202
        end
      end
    end

    it 'I can receive transaction to shared wallet' do
      amt = 1
      amt_ada = 3_000_000
      address = SHARED.addresses.list(@wid_sha)[1]['id']
      target_before = get_shared_balances(@wid_sha)
      src_before = get_shelley_balances(@wid)

      payload = [{ 'address' => address,
                   'amount' => { 'quantity' => amt_ada, 'unit' => 'lovelace' },
                   'assets' => [{ 'policy_id' => ASSETS[0]['policy_id'],
                                  'asset_name' => ASSETS[0]['asset_name'],
                                  'quantity' => amt },
                                { 'policy_id' => ASSETS[1]['policy_id'],
                                  'asset_name' => ASSETS[1]['asset_name'],
                                  'quantity' => amt }] }]

      tx_sent = SHELLEY.transactions.create(@wid, PASS, payload)

      expect(tx_sent).to be_correct_and_respond 202
      expect(tx_sent.to_s).to include 'pending'
      wait_for_tx_in_ledger(@wid, tx_sent['id'])

      target_after = get_shared_balances(@wid_sha)
      src_after = get_shelley_balances(@wid)
      fee = SHELLEY.transactions.get(@wid, tx_sent['id'])['fee']['quantity']

      verify_ada_balance(src_after, src_before,
                         target_after, target_before,
                         amt_ada, fee)

      verify_asset_balance(src_after, src_before,
                           target_after, target_before,
                           amt)
    end
  end

  describe 'E2E Migration' do
    it 'I can migrate all funds back to fixture shared wallet' do
      address = SHARED.addresses.list(@wid_sha)[0]['id']
      src_before = get_shelley_balances(@target_id)
      target_before = get_shared_balances(@wid_sha)

      migration = SHELLEY.migrations.migrate(@target_id, PASS, [address])
      tx_ids = migration.map { |m| m['id'] }
      fees = migration.map { |m| m['fee']['quantity'] }.sum
      amounts = migration.map { |m| m['amount']['quantity'] }.sum - fees
      tx_ids.each do |tx_id|
        wait_for_tx_in_ledger(@target_id, tx_id)
      end
      src_after = get_shelley_balances(@target_id)
      target_after = get_shared_balances(@wid_sha)
      expected_src_balance = { 'total' => 0,
                               'available' => 0,
                               'rewards' => 0,
                               'assets_total' => [],
                               'assets_available' => [] }

      expect(src_after).to eq expected_src_balance

      verify_ada_balance(src_after, src_before,
                         target_after, target_before,
                         amounts, fees)

      tx_ids.each do |tx_id|
        # examine the tx in history
        # on src wallet
        tx = SHELLEY.transactions.get(@target_id, tx_id)
        tx_inputs(tx, present: true)
        tx_outputs(tx, present: true)
        tx_direction(tx, 'outgoing')
        tx_script_validity(tx, 'valid')
        tx_status(tx, 'in_ledger')
        tx_collateral(tx, present: false)
        tx_collateral_outputs(tx, present: false)
        tx_metadata(tx, nil)
        tx_deposits(tx, deposit_taken: 0, deposit_returned: 0)
        tx_withdrawals(tx, present: false)
        tx_mint_burn(tx, mint: [], burn: [])
        tx_extra_signatures(tx, present: false)
        tx_script_integrity(tx, present: false)
        tx_validity_interval_default(tx)
        tx_certificates(tx, present: false)

        # on target wallet
        txt = SHARED.transactions.get(@wid_sha, tx_id)
        tx_fee(txt, 0)
        tx_inputs(txt, present: true)
        tx_outputs(txt, present: true)
        tx_direction(txt, 'incoming')
        tx_script_validity(txt, 'valid')
        tx_status(txt, 'in_ledger')
        tx_collateral(txt, present: false)
        tx_collateral_outputs(txt, present: false)
        tx_metadata(txt, nil)
        tx_deposits(txt, deposit_taken: 0, deposit_returned: 0)
        tx_withdrawals(txt, present: false)
        tx_mint_burn(txt, mint: [], burn: [])
        tx_extra_signatures(txt, present: false)
        tx_script_integrity(txt, present: false)
        tx_validity_interval_default(txt)
        tx_certificates(txt, present: false)
      end
    end
  end
end

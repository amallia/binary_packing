/**
 * Copyright 2018-present Antonio Mallia <me@antoniomallia.it>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "benchmark/benchmark.h"
#include "../external/FastPFor/headers/codecfactory.h"


class RandomValuesFixture : public ::benchmark::Fixture {

    static std::vector<uint32_t> generate_random_vector(size_t n) {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::vector<uint32_t> values(n);
        std::uniform_int_distribution<> dis(uint32_t(0));
        std::generate(values.begin(), values.end(), [&](){ return dis(gen); });
        return values;
    }

public:
    using ::benchmark::Fixture::SetUp;
    using ::benchmark::Fixture::TearDown;

    virtual void SetUp(::benchmark::State& st) {
        using namespace FastPForLib;

        IntegerCODEC &codec = *CODECFactory::getFromName("simdbinarypacking");

        std::vector<uint32_t> values = generate_random_vector(st.range(0));
        encoded_values.resize(values.size() * 8);
        size_t compressedsize = 0;
        codec.encodeArray(values.data(), values.size(), encoded_values.data(),
                compressedsize);
        encoded_values.resize(compressedsize);
        encoded_values.shrink_to_fit();

        decoded_values.resize(values.size());
    }

    virtual void TearDown(::benchmark::State&) {
        encoded_values.clear();
        decoded_values.clear();
    }

    std::vector<uint32_t>  encoded_values;
    std::vector<uint32_t> decoded_values;
};


BENCHMARK_DEFINE_F(RandomValuesFixture, decode)(benchmark::State& state) {
    using namespace FastPForLib;
    IntegerCODEC &codec = *CODECFactory::getFromName("simdbinarypacking");

    while (state.KeepRunning()) {
          size_t recoveredsize = 0;
          codec.decodeArray(encoded_values.data(), encoded_values.size(),
                    decoded_values.data(), recoveredsize);
    }
}
BENCHMARK_REGISTER_F(RandomValuesFixture, decode)->Range(1ULL<<14, 1ULL<<28);

// static void decode(benchmark::State &state) {
//     while (state.KeepRunning()) {
//         // state.PauseTiming();
//         // auto n   = state.range(0);
//         // auto min = 1;
//         // auto max = state.range(0)+2;

//         // std::vector<uint32_t> values = generate_random_vector(state.range(0));
//         // std::vector<uint8_t>  buffer(values.size() * 8);
//         // cuda_bp::encode(buffer.data(), values.data(), values.size());
//         // std::vector<uint32_t> decoded_values(values.size());
//         // state.ResumeTiming();
//         // cuda_bp::decode(decoded_values.data(), buffer.data(), values.size());
//     }
// }

// BENCHMARK(decode)->Range(1ULL<<28, 1ULL<<30);


BENCHMARK_MAIN();


// 2018-11-30 09:07:33
// Running ./bench/simdbp_bench
// Run on (40 X 3300 MHz CPU s)
// CPU Caches:
//   L1 Data 32K (x20)
//   L1 Instruction 32K (x20)
//   L2 Unified 256K (x20)
//   L3 Unified 25600K (x2)
// ***WARNING*** CPU scaling is enabled, the benchmark real time measurements may be noisy and will incur extra overhead.
// ----------------------------------------------------------------------------
// Benchmark                                     Time           CPU Iterations
// ----------------------------------------------------------------------------
// RandomValuesFixture/decode/16384           4886 ns       4885 ns     118584
// RandomValuesFixture/decode/32768           9374 ns       9340 ns      83961
// RandomValuesFixture/decode/262144         98812 ns      98756 ns       7701
// RandomValuesFixture/decode/2097152      1061515 ns    1060834 ns        791
// RandomValuesFixture/decode/16777216    13501458 ns   13501060 ns         58
// RandomValuesFixture/decode/134217728  201160836 ns  201150623 ns          6
// RandomValuesFixture/decode/268435456  206584062 ns  206573748 ns          3
//
module Auditory
import DSP: Filter, TFFilter, BiquadFilter, SOSFilter, filt
import Base: convert
export erb_space, make_erb_filterbank, erb_filterbank, compute_modulation_cfs, make_modulation_filter, modulation_filterbank

immutable ERBFilterbank{C,G,T}
	filters::Vector{SOSFilter{C,G}}
	ERB::Vector{T}
end

function filt(fb::ERBFilterbank, x)
	output = zeros(length(x), length(fb.filters))
	for k = 1:length(fb.filters)
		output[:, k] = filt(fb.filters[k], x)
	end
	return output
end

function make_erb_filterbank(fs, num_channels, low_freq, EarQ = 9.26449, minBW = 24.7, order = 1)
    T = 1/fs
    if length(num_channels) == 1
	cf = erb_space(low_freq, fs/2, num_channels)
    else
	cf = num_channels
	if size(cf,2) > size(cf,1)
	    cf = cf'
	end
    end
    ERB = ((cf/EarQ).^order .+ minBW^order).^(1/order)
    B = 1.019*2*pi*ERB
    B0 = T
    B2 = 0.0
    A0 = 1.0
    A1 = -2*cos(2*cf*pi*T)./exp(B*T)
    A2 = exp(-2*B*T)

    B11 = -(2*T*cos(2*cf*pi*T)./exp(B*T) .+ 2*sqrt(3+2^1.5)*T*sin(2*cf*pi*T)./exp(B*T))/2
    B12 = -(2*T*cos(2*cf*pi*T)./exp(B*T) .- 2*sqrt(3+2^1.5)*T*sin(2*cf*pi*T)./exp(B*T))/2
    B13 = -(2*T*cos(2*cf*pi*T)./exp(B*T) .+ 2*sqrt(3-2^1.5)*T*sin(2*cf*pi*T)./exp(B*T))/2
    B14 = -(2*T*cos(2*cf*pi*T)./exp(B*T) .- 2*sqrt(3-2^1.5)*T*sin(2*cf*pi*T)./exp(B*T))/2

    gain = abs((-2*exp(4*im*cf*pi*T)*T + 2*exp(-(B*T) +
      2*im*cf*pi*T).*T.*(cos(2*cf*pi*T) - sqrt(3 - 2^(3/2))*
      sin(2*cf*pi*T))) .* (-2*exp(4*im*cf*pi*T)*T + 2*exp(-(B*T) +
      2*im*cf*pi*T).*T.* (cos(2*cf*pi*T) + sqrt(3 - 2^(3/2)) *
      sin(2*cf*pi*T))).* (-2*exp(4*im*cf*pi*T)*T + 2*exp(-(B*T) +
      2*im*cf*pi*T).*T.* (cos(2*cf*pi*T) - sqrt(3 +
      2^(3/2))*sin(2*cf*pi*T))) .* (-2*exp(4*im*cf*pi*T)*T +
      2*exp(-(B*T) + 2*im*cf*pi*T).*T.* (cos(2*cf*pi*T) + sqrt(3 +
      2^(3/2))*sin(2*cf*pi*T))) ./ (-2 ./ exp(2*B*T) -
      2*exp(4*im*cf*pi*T) + 2*(1 + exp(4*im*cf*pi*T))./exp(B*T)).^4)	
	
	C = typeof(B0)
	filters = Array(SOSFilter{C,C}, num_channels)
	for ch=1:num_channels
		biquads = Array(BiquadFilter{C}, 4)
		biquads[1] = BiquadFilter(B0, B11[ch], B2, A0, A1[ch], A2[ch])
		biquads[2] = BiquadFilter(B0, B12[ch], B2, A0, A1[ch], A2[ch])
		biquads[3] = BiquadFilter(B0, B13[ch], B2, A0, A1[ch], A2[ch])
		biquads[4] = BiquadFilter(B0, B14[ch], B2, A0, A1[ch], A2[ch])
		filters[ch] = SOSFilter(biquads, 1/gain[ch])
	end
	ERBFilterbank(filters, ERB)
end

function erb_space(low_freq, high_freq, num_channels, EarQ = 9.26449, minBW = 24.7, order = 1)
    # All of the following expressions are derived in Apple TR #35, "An
    # Efficient Implementation of the Patterson-Holdsworth Cochlear
    # Filter Bank."  See pages 33-34.
    cfArray = -(EarQ*minBW) .+ exp([1:num_channels]*(-log(high_freq + EarQ*minBW) + log(low_freq + EarQ*minBW))/num_channels) * (high_freq + EarQ*minBW)
end

immutable ModulationFilterbank{T}
	filters::Vector{BiquadFilter{T}}
end

function filt(fb::ModulationFilterbank, x)
	output = zeros(length(x), length(fb.filters))
	@inbounds begin
		for k=1:length(fb.filters)
			output[:,k] = filt(fb.filters[k], x)
		end
	end
	return output
end

function make_modulation_filter(w0, Q)
    W0 = tan(w0/2)
    B0 = W0/Q
    b = [B0, 0, -B0]
    a = [(1 + B0 + W0^2), (2*W0^2 - 2), (1 - B0 + W0^2)]
    BiquadFilter(b[1], b[2], b[3], a[1], a[2], a[3])
end

function modulation_filterbank(mf, fs, q)
    ModulationFilterbank([make_modulation_filter(w0, q) for w0 in 2*pi*mf/fs])
end

function compute_modulation_cfs(min_cf, max_cf, n)
    spacing_factor = (max_cf/min_cf)^(1/(n-1))
    cfs = zeros(n)
    cfs[1] = min_cf
    for k=2:n
        cfs[k] = cfs[k-1]*spacing_factor
    end
    return cfs
end

end #module
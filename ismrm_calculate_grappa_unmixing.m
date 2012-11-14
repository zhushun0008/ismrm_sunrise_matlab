function [unmix] = ismrm_calculate_grappa_unmixing(source_data, kernel_size, acc_factor, csm, target_data, data_mask, verbose)
%
%   [unmix] = ismrm_calculate_grappa_unmixing(source_data, kernel_size, acc_factor, csm, target_data, data_mask, verbose)
%   
%   Calculates b1-weights image space GRAPPA unmixing coefficients.
%
%   INPUT:
%       source_data [kx,ky,coil]   : Source data for grappa kernel estimation (k-space)
%       kernel_size [kx,ky]        : e.g. [4 5]
%       acc_factor  scalar         : Acceleration factor, e.g. 2
%       csm         [x,y,c]        : Coil sensitivity map
%       target_data [kx,ky,coil]   : Target coil data, defaults to source data
%       data_mask   [kx,ky]        : '1' = calibration data, '0' = ignore
%       verbode     bool           : Set true for verbose output
%
%   OUTPUT:
%       unmix [x,y,coil]           : Image unmixing coefficients
%
%   Typical usage:
%       [unmix] = calculate_grappa_unmixing(source_data, [5 4], 4, csm);
%
%
%   Code made available for the ISMRM 2013 Sunrise Educational Course
% 
%   Michael S. Hansen (michael.hansen@nih.gov)
%   Philip Beatty (philip.beatty@sri.utoronto.ca)
%

if nargin < 4,
   error('At least 4 arguments needed'); 
end

if nargin < 5,
    target_data = [];
end

if nargin < 6,
    data_mask = [];
end

if nargin < 7,
    verbose = false;
end

if (isempty(target_data)),
        target_data = source_data;
end


if (isempty(data_mask)),
    data_mask = ones(size(source_data,1),size(source_data,2));
end

if (length(size(source_data)) == 2),
    coils = 1;
else
    coils = size(source_data,length(size(source_data)));
end

if (length(size(target_data)) == 2),
    target_coils = 1;
else
    target_coils = size(target_data,length(size(target_data)));
end

%Number of coefficients to calculate for each undersampled position, i.e.
%the number of unknowns
coefficients = kernel_size(1)*kernel_size(2)*coils;


%Ranges where we have data which can be used for reference calculation
[d1_min,d2_min] = ind2sub(size(data_mask),find(data_mask,1,'first'));
[d1_max,d2_max] = ind2sub(size(data_mask),find(data_mask,1,'last'));
d1_range = (bitshift(kernel_size(1),-1)+d1_min):(d1_max-bitshift(kernel_size(1)+1,-1));
d2_range = (bitshift(kernel_size(2)*acc_factor,-1)+d2_min):(d2_max-bitshift(kernel_size(2)*acc_factor+1,-1));

%In how many k-space locations will we be able to estimate the kernel, i.e.
%the number of equations
k_locations = length(d1_range)*length(d2_range);

kernel = zeros(kernel_size(1),kernel_size(2)*acc_factor,coils,target_coils);

if (verbose),
    fprintf('Calculating grappa kernels...\n');
end

for s=1:(acc_factor),
    if (verbose),
        fprintf('Inversions %d of %d...', s, (acc_factor));
    end
    A = zeros(k_locations,coefficients);
    b = zeros(k_locations,target_coils);
    
    k_loc_counter = 1;
    for d1=d1_range,
        d1_vals = [d1:d1+kernel_size(1)-1]-bitshift(kernel_size(1),-1);
        for d2=d2_range,
            d2_vals = d2+(([0:(kernel_size(2)-1)]*acc_factor)+(s)-bitshift(size(kernel,2),-1)-1)+1;
            A(k_loc_counter,:) = vec(source_data(d1_vals,d2_vals,:));
            b(k_loc_counter,:) = target_data(d1,d2,:);
            k_loc_counter = k_loc_counter + 1;
        end
    end
    
    if (verbose),
        fprintf('inverting...');
    end
    
    %No regularization
    %A_inv = pinv( A'*A)*A';

    %Tikhonov
    S = svd(A,0);
    A_inv = pinv(A'*A + eye(size(A'*A)).*(1e-3*max(abs(S(:)))).^2)*A';
    
    kernel_set = A_inv*b;
    for c=1:target_coils,
        kernel(:,([0:(kernel_size(2)-1)]*acc_factor)+(s+1),:,c) = reshape(kernel_set(:,c),kernel_size(1),kernel_size(2),coils);
    end
    if (verbose),
        fprintf('done.\n');
    end
end


kernel = flipdim(flipdim(kernel,1),2); %Flip dimensions in preparation for convolution.


unmix = zeros(size(source_data));
if (nargout > 2),
   unmix_sc = zeros(size(unmix,1),size(unmix,2),coils,coils); 
end

if (verbose),
    fprintf('Doing B1 weighted combination....');
end

for c=1:target_coils,
    kernel_pad = pad_grappa_kernel(kernel(:,:,:,c),size(target_data));
    kernel_pad = fftshift(ifft(ifftshift(kernel_pad,1),[],1),1);
    kernel_pad = fftshift(ifft(ifftshift(kernel_pad,2),[],2),2);
    kernel_pad = kernel_pad*(size(kernel_pad,1)*size(kernel_pad,2)/acc_factor);
    if (nargout > 2),
        unmix_sc(:,:,:,c) = kernel_pad;
    end 
    csm_rss = sqrt(sum(conj(csm).*csm,3));
    csm_rss(csm_rss < realmin('single')) = 1; %Avoid devision by zeros where coils are undefined
    unmix = unmix + (kernel_pad .* repmat(conj(csm(:,:,c) ./ csm_rss),[1 1 coils]));
end

if (verbose),
    fprintf('done.\n');
end

return


function padded_kernel = pad_grappa_kernel(gkernel, image_size)
    padded_kernel = zeros(image_size(1),image_size(2),size(gkernel,3));
    padded_kernel([1:size(gkernel,1)]+bitshift(image_size(1)-size(gkernel,1)-1,-1)+1, ...
        [1:size(gkernel,2)]+bitshift(image_size(2)-size(gkernel,2)-1,-1)+1, :) = gkernel;
return
        
